import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Egyszeri lekérdezés, amely hálózat nélkül sem akad el: offline állapotban
/// azonnal a Firestore helyi gyorsítótárából olvas, online pedig legfeljebb
/// [timeout] ideig vár a szerverre, utána szintén a gyorsítótárra vált
/// (csatlakozott, de valójában halott hálózatnál a szerveres lekérés
/// különben sokáig függne).
Future<QuerySnapshot<T>> getWithOfflineFallback<T>(
  Query<T> query, {
  required bool online,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!online) {
    return query.get(const GetOptions(source: Source.cache));
  }
  try {
    return await query.get().timeout(timeout);
  } catch (_) {
    return query.get(const GetOptions(source: Source.cache));
  }
}
