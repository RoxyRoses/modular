import 'package:meta/meta.dart';

import '../../modular_core.dart';

class _MutableValue {
  bool isReadyFlag = false;
}

///Abstract class [BindContextImpl]
///Manage binds
abstract class BindContextImpl implements BindContext {
  @override
  @visibleForOverriding
  List<BindContract> get binds => const [];
  @override
  @visibleForOverriding
  List<BindContext> get imports => const [];

  final _mutableValue = _MutableValue();

  final List<BindContract> _binds = [];
  @internal

  ///[String] [Set] variable
  final Set<String> tags = {};
  final _singletonBinds = <Type, BindEntry>{};

  @override
  List<BindEntry> get instanciatedSingletons => _singletonBinds.values.toList();

  @override
  @visibleForTesting
  List<BindContract> getProcessBinds() =>
      _binds.where((element) => !element.export).toList();
  @override
  void changeBinds(List<BindContract> newBinds) {
    _binds
      ..removeWhere((element) => !element.alwaysSerialized)
      ..addAll(newBinds);
  }

///Adds binds into the BindContract [List]
///adds export binds for each module in [imports]
  BindContextImpl() {
    _binds.addAll(binds);
    for (final module in imports) {
      _addExportBinds((module as BindContextImpl)._binds);
    }
  }

  void _addExportBinds(List<BindContract> bindsForOtherModule) {
    final filteredList = bindsForOtherModule.where((element) => element.export);
    _binds.insertAll(0, filteredList.map((e) => e.copyWith(export: false)));
  }

  @override
  BindEntry<T>? getBind<T extends Object>(Injector injector) {
    T bindValue;
    final type = _getInjectType<T>();
    if (_singletonBinds.containsKey(type)) {
      return _singletonBinds[type]!.cast<T>();
    }

    final bind = getProcessBinds().firstWhere(
      (b) => b.factoryFunction is T Function(Injector),
      orElse: () => BindEmpty(),
    );
    if (bind is BindEmpty) {
      return null;
    }

    bindValue = bind.factoryFunction(injector) as T;
    final entry = BindEntry<T>(value: bindValue, bind: bind.cast<T>());
    if (bind.isSingleton) {
      _singletonBinds[type] = entry;
    }

    return entry;
  }

  @override
  @mustCallSuper
  bool remove<T>() {
    final type = _getInjectType<T>();
    if (_singletonBinds.containsKey(type)) {
      final singletonBind = _singletonBinds[type]!;
      _executeDisposeImplementation(singletonBind);
      _singletonBinds.remove(type);
      return true;
    } else {
      return false;
    }
  }
///Removes a bind in scope
  bool removeScopedBind() {
    final totalBind = _singletonBinds.length;
    _singletonBinds.removeWhere((key, singletonBind) {
      if (singletonBind.bind.isScoped) {
        _executeDisposeImplementation(singletonBind);
        return true;
      }
      return false;
    });

    return totalBind != _singletonBinds.length;
  }

  @override
  @mustCallSuper
  void dispose() {
    for (final key in _singletonBinds.keys) {
      final singletonBind = _singletonBinds[key]!;
      _executeDisposeImplementation(singletonBind);
    }
    _singletonBinds.clear();
  }

  @override
  @mustCallSuper
  Future<void> isReady() async {
    if (_mutableValue.isReadyFlag) return;
    _mutableValue.isReadyFlag = true;
    final asyncBindList =
        getProcessBinds().whereType<AsyncBindContract>().toList();
    for (final bind in asyncBindList) {
      final resolvedBind = await bind.convertToBind();
      _binds.insert(0, resolvedBind);
    }
  }

///Instantiate singleton binds
  @mustCallSuper
  void instantiateSingletonBinds(
    List<BindEntry> singletons,
    Injector injector,
  ) {
    final filteredList = getProcessBinds()
        .where((bind) => !bind.isLazy && !_containBind(singletons, bind));
    for (final bindElement in filteredList) {
      final b = bindElement.factoryFunction(injector);
      if (!_singletonBinds.containsKey(b.runtimeType)) {
        _singletonBinds[b.runtimeType] = _generateBindEntry(b, bindElement);
      }
    }
  }

  BindEntry<T> _generateBindEntry<T extends Object>(T value, bind) {
    return BindEntry<T>(value: value, bind: bind);
  }

  bool _containBind(List<BindEntry> singletons, BindContract bind) {
    return singletons.indexWhere(
          (element) => element.bind.factoryFunction == bind.factoryFunction,
        ) !=
        -1;
  }

  Type _getInjectType<B>() {
    var foundType = B;

    for (final singleton in _singletonBinds.values) {
      if (singleton.value is B) {
        foundType = _singletonBinds.entries
            .firstWhere((map) => map.value.value == singleton.value)
            .key;
        break;
      }
    }

    return foundType;
  }

  void _executeDisposeImplementation(BindEntry singletonBind) {
    final value = singletonBind.value;
    if (value is Disposable) {
      value.dispose();
    } else {
      singletonBind.dispose();
    }
  }
}
