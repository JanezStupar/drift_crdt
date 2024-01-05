import 'package:json_annotation/json_annotation.dart';

abstract class BaseCrdtSerializable {
  dynamic id;

  String hlc;

  @JsonKey(name: 'node_id')
  String nodeId;

  String modified;

  @JsonKey(name: 'is_deleted')
  int isDeleted;

  BaseCrdtSerializable(
      this.id, this.hlc, this.nodeId, this.modified, this.isDeleted);
}
