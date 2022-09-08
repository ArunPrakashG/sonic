import 'package:sonic/sonic.dart';
import 'package:sonic/src/base_configuration.dart';

Future<void> main() async {
  final sonic = Sonic(
    baseConfiguration: BaseConfiguration.defaultConfig(),
  );

  sonic.initialize();
}
