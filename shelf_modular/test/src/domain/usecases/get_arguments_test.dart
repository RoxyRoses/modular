import 'package:mocktail/mocktail.dart';
import 'package:modular_core/modular_core.dart';
import 'package:shelf_modular/src/domain/usecases/get_arguments.dart';
import 'package:shelf_modular/src/shared/either.dart';
import 'package:test/test.dart';

import '../../mocks/mocks.dart';

void main() {
  final service = RouteServiceMock();
  final usecase = GetArgumentsImpl(service);
  test('get ModularArguments', () {
    final args = ModularArguments.empty();
    when(service.getArguments).thenReturn(right(args));

    expect(usecase.call().getOrElse((left) => ModularArguments.empty()), args);
  });
}
