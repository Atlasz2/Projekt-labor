import 'dart:async';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class PendingAction {
  final String id;
  final String actionType;
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  PendingAction({
    required this.id,
    required this.actionType,
    required this.collection,
    required this.docId,
    required this.data,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'actionType': actionType,
    'collection': collection,
    'docId': docId,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
    id: json['id'] as String,
    actionType: json['actionType'] as String,
    collection: json['collection'] as String,
    docId: json['docId'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class OfflineSyncService {
  OfflineSyncService._internal();

  static final OfflineSyncService _instance = OfflineSyncService._internal();

  factory OfflineSyncService() => _instance;

  late Box<Map> _pendingActionsBox;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityTimer;
  bool _initialized = false;
  bool _syncInProgress = false;
  bool _isOnline = false;

  final ValueNotifier<bool> onlineNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  bool get isOnline => _isOnline;
  int get pendingActionCount =>
      _pendingActionsBox.isOpen ? _pendingActionsBox.length : 0;

  Future<void> init() async {
    if (_initialized) return;
    _pendingActionsBox = await Hive.openBox<Map>('pending_actions');
    _initialized = true;
    _refreshPendingCount();

    final initialConnectivity = await Connectivity().checkConnectivity();
    await _updateConnectivity(initialConnectivity);

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      await _updateConnectivity(results);
      if (_isOnline) {
        unawaited(syncPendingActions());
      }
    });

    _connectivityTimer = Timer.periodic(const Duration(seconds: 60), (
      _,
    ) async {
      final latestConnectivity = await Connectivity().checkConnectivity();
      await _updateConnectivity(latestConnectivity);
      if (_isOnline) {
        unawaited(syncPendingActions());
      }
    });
  }

  Future<void> _updateConnectivity(List<ConnectivityResult> results) async {
    final hasInterface = results.any((item) => item != ConnectivityResult.none);
    if (!hasInterface) {
      _setOnline(false);
      return;
    }

    try {
      await _firestore
          .collection('trips')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      _setOnline(true);
    } catch (_) {
      _setOnline(false);
    }
  }

  void _setOnline(bool value) {
    _isOnline = value;
    if (onlineNotifier.value != value) {
      onlineNotifier.value = value;
    }
  }

  void _refreshPendingCount() {
    pendingCountNotifier.value = pendingActionCount;
  }

  Future<void> queueAction({
    required String actionType,
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final action = PendingAction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      actionType: actionType,
      collection: collection,
      docId: docId,
      data: data,
      createdAt: DateTime.now(),
    );

    await _pendingActionsBox.put(action.id, action.toJson());
    _refreshPendingCount();
  }

  Future<void> syncPendingActions() async {
    if (!_initialized || !_isOnline || _syncInProgress) return;

    _syncInProgress = true;
    try {
      final actions =
          _pendingActionsBox.values
              .map(
                (value) =>
                    PendingAction.fromJson(Map<String, dynamic>.from(value)),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final action in actions) {
        try {
          final docRef = _firestore
              .collection(action.collection)
              .doc(action.docId);

          switch (action.actionType) {
            case 'create':
              await docRef.set(action.data, SetOptions(merge: true));
              break;
            case 'update':
              await docRef.set(action.data, SetOptions(merge: true));
              break;
            case 'delete':
              await docRef.delete();
              break;
          }

          await _pendingActionsBox.delete(action.id);
          _refreshPendingCount();
        } catch (error) {
          debugPrint('Offline sync hiba: $error');
        }
      }
    } finally {
      _syncInProgress = false;
    }
  }

  DateTime? getLastSyncTime() {
    if (!_initialized || _pendingActionsBox.isEmpty) return null;

    final actions = _pendingActionsBox.values
        .map(
          (value) => PendingAction.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
    if (actions.isEmpty) return null;
    actions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return actions.last.createdAt;
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
  }
}
