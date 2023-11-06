import 'package:drift_crdt/serializable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'serializable.g.dart';

@JsonSerializable()
class User extends BaseCrdtSerializable {
  final String name;

  @JsonKey(name: 'birth_date')
  final num birthDate;

  @JsonKey(name: 'profile_picture')
  final String? profilePicture;

  final String? preferences;

  User(int id, String hlc, String nodeId, String modified, int isDeleted, this.name,
      this.birthDate, this.profilePicture, this.preferences)
      : super(id, hlc, nodeId, modified, isDeleted);

  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);

  Map<String, Object?> toJson() => _$UserToJson(this);

  @override
  String toString() {
    return 'User{name: $name}';
  }
}
