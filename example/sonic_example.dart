// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:developer';

import 'package:sonic/sonic.dart';

class ExampleResponse {}

Future<void> main() async {
  final sonic = Sonic.initialize(
    baseConfiguration: BaseConfiguration.defaultConfig(),
  );

  final response = await sonic
      .create<MockApiModel>(
        url: 'https://jsonplaceholder.typicode.com/todos/1',
      )
      .get()
      .withDecoder((dynamic json) => MockApiModel.fromMap(json))
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
}

class MockApiModel {
  final int userId;
  final int id;
  final String title;
  final bool completed;

  MockApiModel({
    required this.userId,
    required this.id,
    required this.title,
    required this.completed,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'userId': userId,
      'id': id,
      'title': title,
      'completed': completed,
    };
  }

  factory MockApiModel.fromMap(dynamic map) {
    return MockApiModel(
      userId: map['userId'] as int,
      id: map['id'] as int,
      title: map['title'] as String,
      completed: map['completed'] as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory MockApiModel.fromJson(String source) =>
      MockApiModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
