import 'package:sonic/sonic.dart';
import 'package:sonic/src/base_configuration.dart';

class ExampleResponse {}

Future<void> main() async {
  final sonic = Sonic(
    baseConfiguration: BaseConfiguration.defaultConfig(),
  );

  sonic.initialize();
  final response = await sonic
      .create<ExampleResponse>(url: '')
      .put()
      .withHeader('', '')
      .execute();

  response.to<String>(
    (data) {
      return data.message ?? '';
    },
  );
}
