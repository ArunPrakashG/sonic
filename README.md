<center>
    <h1>Sonic</h1>
     <p>
        An HTTP Client with a Fluent interface and an improved type support.
    </p>
</center>

## Features
- Fluent Interface
- Concurrency Control
- Response Type Caching
- Flutter friendly, with methods designed for ease of use with flutter.

## Getting Started

- Add the latest version of the package from pubspec.
- Import the package: `import 'package:sonic/sonic.dart';`
- Initialize the client:
    ```dart
    final sonic = Sonic(
    baseConfiguration: const BaseConfiguration(
      baseUrl: YOUR_BASE_URL,
      debugMode: true,
    ),
  );

  sonic.initialize();
  ```
- Use the `create` method to create a new request builder.
    ```dart
    await sonic
      .create<YOUR_RESPONSE_TYPE>(url: YOUR_PATH_OR_FULL_URL)
      .withDecoder((dynamic json) => YOUR_RESPONSE_TYPE.fromMap(json))
      .get()
      .execute();
    ```
- the response of this async operation will be `SonicResponse<T>` where T will be `YOUR_RESPONSE_TYPE`

## Usage

```dart
  final sonic = Sonic(
    baseConfiguration: const BaseConfiguration(
      baseUrl: 'https://jsonplaceholder.typicode.com/',
      debugMode: true,
    ),
  );

  sonic.initialize();

  final response = await sonic
      .create<TodoModel>(url: '/todos/1')
      .get()
      .withDecoder((dynamic json) => TodoModel.fromMap(json))
      .onError((error) {
        print(error.message);
        print(error.stackTrace);
      })
      .onSuccess(
        (data) {
          print(data.data?.title);
        },
      )
      .onLoading(() => log('Loading'))
      .execute();
```

## NOTES
- You can also get raw response and ignore the type parsing by using `asRawRequest()` builder method and specifying the type parameter as `dynamic`
- You wont need to pass decoder using `withDecoder` after the first call to the same type as the decoder will be cached based on the type.
- You can either pass relative url (path) or an absolute url to the `url` named parameter.
- If `debugMode` is true, `LogInterceptor` will be added to the internal `Dio` instance and it will be used to log everything related to a network call in the standard output.

## Contributions

Contributions are always welcome!
