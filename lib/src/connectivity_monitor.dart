import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstract contract for monitoring device network connectivity.
abstract class ConnectivityMonitor {
  /// Whether the device currently has an active Internet connection.
  Future<bool> get isConnected;

  /// Stream emitting boolean connection status changes (`true` = online, `false` = offline).
  Stream<bool> get onConnectivityChanged;

  /// Disposes resources and listeners.
  void dispose();
}

/// Default implementation using [Connectivity] from `connectivity_plus`
/// with optional DNS / socket reachability check.
class DefaultConnectivityMonitor implements ConnectivityMonitor {
  final Connectivity _connectivity;
  final bool checkRealInternet;
  final String testHost;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _lastStatus = true;

  DefaultConnectivityMonitor({
    Connectivity? connectivity,
    this.checkRealInternet = true,
    this.testHost = '1.1.1.1',
  }) : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((dynamic result) async {
      final connected = await _evaluate(result);
      if (connected != _lastStatus) {
        _lastStatus = connected;
        _controller.add(connected);
      }
    });
  }

  @override
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    _lastStatus = await _evaluate(result);
    return _lastStatus;
  }

  Future<bool> _evaluate(dynamic result) async {
    bool hasInterface = false;

    if (result is List<ConnectivityResult>) {
      hasInterface = result.any((r) => r != ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      hasInterface = result != ConnectivityResult.none;
    }

    if (!hasInterface) return false;
    if (!checkRealInternet) return true;

    // Optional quick socket ping
    try {
      final socket = await Socket.connect(
        testHost,
        53,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      // If direct ping fails, fallback to interface presence
      return true;
    }
  }

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

/// Controllable mock connectivity monitor for testing and simulation.
class MockConnectivityMonitor implements ConnectivityMonitor {
  bool _connected;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  MockConnectivityMonitor({bool initialConnected = true})
      : _connected = initialConnected;

  @override
  Future<bool> get isConnected async => _connected;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Manually change the connection state and notify listeners.
  void setConnected(bool connected) {
    if (_connected != connected) {
      _connected = connected;
      _controller.add(connected);
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
