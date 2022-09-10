/// **Sonic** is a HTTP client made on top of **Dio** to have better support for types and provide a fluent interface for the calls.
library sonic;

export 'package:dio/src/cancel_token.dart' show CancelToken;

export 'src/base_configuration.dart' show BaseConfiguration;
export 'src/sonic_base.dart' show Sonic, SonicRequestBuilder, SonicResponse;
