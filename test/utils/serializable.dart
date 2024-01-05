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

  User(int super.id, super.hlc, super.nodeId, super.modified, super.isDeleted,
      this.name, this.birthDate, this.profilePicture, this.preferences);

  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);

  Map<String, Object?> toJson() => _$UserToJson(this);

  @override
  String toString() {
    return 'User{name: $name}';
  }
}
