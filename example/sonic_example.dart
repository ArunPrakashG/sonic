// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:developer';

import 'package:sonic/sonic.dart';

Future<void> main() async {
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
}

class TodoModel {
  final int userId;
  final int id;
  final String title;
  final bool completed;

  TodoModel({
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

  factory TodoModel.fromMap(dynamic map) {
    return TodoModel(
      userId: map['userId'] as int,
      id: map['id'] as int,
      title: map['title'] as String,
      completed: map['completed'] as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory TodoModel.fromJson(String source) =>
      TodoModel.fromMap(json.decode(source) as Map<String, dynamic>);
}
