// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializable.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      (json['id'] as num).toInt(),
      json['hlc'] as String,
      json['node_id'] as String,
      json['modified'] as String,
      (json['is_deleted'] as num).toInt(),
      json['name'] as String,
      json['birth_date'] as num,
      json['profile_picture'] as String?,
      json['preferences'] as String?,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'hlc': instance.hlc,
      'node_id': instance.nodeId,
      'modified': instance.modified,
      'is_deleted': instance.isDeleted,
      'name': instance.name,
      'birth_date': instance.birthDate,
      'profile_picture': instance.profilePicture,
      'preferences': instance.preferences,
    };
