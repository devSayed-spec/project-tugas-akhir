import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {
  late MqttServerClient client;
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<String?> lastMessage = ValueNotifier(null);
  final ValueNotifier<String?> lastTopic = ValueNotifier(null);

  // Konfigurasi Mosquitto - sesuaikan dengan IP server Anda
  final String broker = '10.10.10.10'; // IP server Mosquitto dari Arduino
  final int port = 1883; // Port default Mosquitto tanpa SSL
  
  // Topik yang sama dengan Arduino
  static const String TOPIC_ENROLL = 'smartlocker/enroll';
  static const String TOPIC_SUCCESS = 'smartlocker/fingerprint/success';
  static const String TOPIC_FAIL = 'smartlocker/fingerprint/fail';
  static const String TOPIC_DENIED = 'smartlocker/fingerprint/denied';
  static const String TOPIC_DUPLICATE = 'smartlocker/fingerprint/duplicate';
  static const String TOPIC_NOT_REGISTERED = 'smartlocker/fingerprint/tidak_terdaftar';

  bool _isReconnecting = false;

  /// Getter untuk cek koneksi secara aman
  bool get isClientConnected =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  /// Koneksi ke broker Mosquitto
  Future<void> connect() async {
    final random = Random();
    final clientId = 'flutter_client_${random.nextInt(10000)}';

    client = MqttServerClient(broker, clientId);
    client.port = port;
    client.secure = false; // Tidak menggunakan SSL
    client.logging(on: false);
    client.keepAlivePeriod = 60; // Sesuai dengan Arduino setKeepAlive(60)
    client.socketTimeout = 10; // Sesuai dengan Arduino setSocketTimeout(10)

    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = (String topic) {
      print('✅ Subscribed to $topic');
    };
    client.pongCallback = () {
      print('📡 Ping response received');
    };

    // Koneksi message tanpa username/password
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean() // Clean session
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      print('🔄 Connecting to Mosquitto broker at $broker:$port...');
      await client.connect();
      
      if (!isClientConnected) {
        print('❌ MQTT connection failed with state: ${client.connectionStatus?.state}');
        client.disconnect();
        return;
      }
      
      print('✅ Connected to Mosquitto broker');
    } catch (e) {
      print('❌ MQTT connection error: $e');
      client.disconnect();
      return;
    }

    // Subscribe ke semua topik status sidik jari yang sama dengan Arduino
    subscribe(TOPIC_SUCCESS);
    subscribe(TOPIC_FAIL);
    subscribe(TOPIC_DENIED);
    subscribe(TOPIC_DUPLICATE);
    subscribe(TOPIC_NOT_REGISTERED);

    // Listen untuk pesan masuk
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;
      
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final topic = c[0].topic;
      
      print('📥 Received message: "$payload" from topic: "$topic"');
      lastMessage.value = payload;
      lastTopic.value = topic;

      // Handler per topik sesuai dengan Arduino
      handleIncomingMessage(topic, payload);
    });
  }

  /// Handler untuk pesan masuk dari Arduino
  void handleIncomingMessage(String topic, String payload) {
    switch (topic) {
      case TOPIC_SUCCESS:
        print('✅ $payload');
        // TODO: Update UI untuk akses berhasil
        break;
        
      case TOPIC_FAIL:
        print('❌ $payload');
        // TODO: Update UI untuk kegagalan
        break;
        
      case TOPIC_DENIED:
        print('⚠️ $payload');
        // TODO: Update UI untuk akses ditolak
        break;
        
      case TOPIC_DUPLICATE:
        print('🔄 $payload');
        // TODO: Handle duplikat sidik jari
        break;
        
      case TOPIC_NOT_REGISTERED:
        print('❓ $payload');
        // TODO: Handle sidik jari tidak terdaftar
        break;
        
      default:
        print('📨 Unknown topic: $topic - $payload');
    }
  }

  /// Kirim perintah enrollment ke Arduino
  /// Format: kelas:id:nama:jempol:sensor
  /// Contoh: "XI-RPL-1:12345:John Doe:kanan:1"
  void enrollFingerprint({
    required String className,
    required String studentId,
    required String studentName,
    required String thumbType, // "kanan" atau "kiri"
    required int sensorNumber, // 1 atau 2
  }) {
    if (!isClientConnected) {
      print('❌ MQTT not connected');
      return;
    }

    final message = '$className:$studentId:$studentName:$thumbType:$sensorNumber';
    publish(TOPIC_ENROLL, message);
    print('📤 Enrollment request sent: $message');
  }

  /// Kirim perintah sistem ke Arduino
  void sendSystemCommand(String command) {
    if (!isClientConnected) {
      print('❌ MQTT not connected');
      return;
    }

    // Perintah sistem yang didukung Arduino:
    // - CLEAR_ALL: Hapus semua sidik jari
    // - LIST_FINGERPRINTS: Tampilkan daftar sidik jari
    // - TEST_SENSOR: Test sensor sidik jari
    // - SHOW_AVG_TIME: Tampilkan rata-rata waktu autentikasi
    publish(TOPIC_ENROLL, command);
    print('📤 System command sent: $command');
  }

  /// Kirim pesan ke topik tertentu
  void publish(String topic, String message) {
    if (!isClientConnected) {
      print('❌ MQTT not connected');
      return;
    }
    
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    print('📤 Published: "$message" to "$topic"');
  }

  /// Berlangganan ke topik tertentu
  void subscribe(String topic) {
    if (!isClientConnected) {
      print('❌ MQTT not connected');
      return;
    }
    client.subscribe(topic, MqttQos.atLeastOnce);
    print('🔔 Subscribed to "$topic"');
  }

  /// Unsubscribe dari topik
  void unsubscribe(String topic) {
    if (!isClientConnected) return;
    client.unsubscribe(topic);
    print('🚫 Unsubscribed from "$topic"');
  }

  /// Disconnect manual
  void disconnect() {
    if (isClientConnected) {
      client.disconnect();
      print('🔌 MQTT manually disconnected');
    }
  }

  /// Callback saat terkoneksi
  void onConnected() {
    print('✅ MQTT connected to Mosquitto broker');
    isConnected.value = true;
  }

  /// Callback saat terputus
  void onDisconnected() {
    print('⚠️ MQTT disconnected from Mosquitto broker');
    isConnected.value = false;

    // Reconnect otomatis dengan delay
    if (!_isReconnecting) {
      _isReconnecting = true;
      Future.delayed(const Duration(seconds: 5), () async {
        print('🔁 Attempting reconnect to Mosquitto...');
        try {
          await connect();
        } catch (e) {
          print('❌ Reconnect failed: $e');
        }
        _isReconnecting = false;
      });
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    isConnected.dispose();
    lastMessage.dispose();
    lastTopic.dispose();
  }
}