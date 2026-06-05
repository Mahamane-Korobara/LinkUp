import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkup_mobile/services/lan_sweep.dart';

void main() {
  group('LanSweepDiscovery.isLikelyWifiInterface', () {
    test('accepts Linux/Android Wi-Fi prefixes', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('wlan0'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('wlan1'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('WLAN0'), isTrue);
    });

    test('accepts Samsung hotspot interface', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('swlan0'), isTrue);
    });

    test('accepts macOS/iOS Wi-Fi pattern enN', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('en0'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('en1'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('en42'), isTrue);
    });

    test('rejects Linux Ethernet patterns (enp/eno/ens)', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('enp0s3'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('eno1'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('ens33'), isFalse);
    });

    test('rejects cellular interfaces', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('rmnet0'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('rmnet_data0'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('ccmni0'), isFalse);
    });

    test('rejects loopback and unrelated names', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('lo'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('docker0'), isFalse);
      expect(LanSweepDiscovery.isLikelyWifiInterface('tun0'), isFalse);
    });

    test('accepts literal "wifi"', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('wifi'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('WiFi'), isTrue);
    });

    test('accepts tethering AP interfaces (phone is hotspot)', () {
      expect(LanSweepDiscovery.isLikelyWifiInterface('ap0'), isTrue);
      expect(LanSweepDiscovery.isLikelyWifiInterface('softap0'), isTrue);
    });
  });

  group('LanSweepDiscovery.isCellularInterface', () {
    test('matches mobile-data interfaces', () {
      for (final n in ['rmnet0', 'rmnet_data1', 'ccmni0', 'pdp_ip0', 'clat4']) {
        expect(LanSweepDiscovery.isCellularInterface(n), isTrue, reason: n);
      }
    });

    test('does not match Wi-Fi / hotspot interfaces', () {
      for (final n in ['wlan0', 'swlan0', 'ap0', 'en0']) {
        expect(LanSweepDiscovery.isCellularInterface(n), isFalse, reason: n);
      }
    });
  });

  group('LanSweepDiscovery.isPrivateIPv4', () {
    test('accepts RFC 1918 ranges', () {
      for (final ip in ['10.0.0.5', '172.16.4.2', '172.31.9.9', '192.168.1.10', '192.168.43.1']) {
        expect(LanSweepDiscovery.isPrivateIPv4(ip), isTrue, reason: ip);
      }
    });

    test('rejects public / CGNAT / malformed', () {
      for (final ip in ['8.8.8.8', '100.64.0.1', '172.32.0.1', '1.2.3', 'abc']) {
        expect(LanSweepDiscovery.isPrivateIPv4(ip), isFalse, reason: ip);
      }
    });
  });

  group('LanSweepDiscovery.probe (retry on timeout)', () {
    test('retries once on TimeoutException, succeeds 2nd attempt', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          // 1er appel : on dépasse le requestTimeout (=100ms) en attendant 250ms
          await Future.delayed(const Duration(milliseconds: 250));
          return http.Response('{}', 200);
        }
        return http.Response(
          '{"service":"linkup-bridge","agent_id":"linkup-test",'
          '"version":"0.1.0","host":"pc","user":"mahamane"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final sweep = LanSweepDiscovery(
        client: mock,
        requestTimeout: const Duration(milliseconds: 100),
        retryBackoff: const Duration(milliseconds: 10),
      );

      final result = await sweep.probe('192.168.1.42');

      expect(callCount, 2, reason: 'retry doit être tenté après timeout');
      expect(result, isNotNull);
      expect(result!.agentId, 'linkup-test');
      expect(result.user, 'mahamane');
      sweep.close();
    });

    test('returns null after 2 timeouts (gives up cleanly)', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        await Future.delayed(const Duration(milliseconds: 250));
        return http.Response('{}', 200);
      });

      final sweep = LanSweepDiscovery(
        client: mock,
        requestTimeout: const Duration(milliseconds: 100),
        retryBackoff: const Duration(milliseconds: 10),
      );

      final result = await sweep.probe('192.168.1.42');
      expect(callCount, 2, reason: '1 essai initial + 1 retry');
      expect(result, isNull);
      sweep.close();
    });

    test('does NOT retry on non-timeout errors (ClientException)', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        throw http.ClientException('connection refused');
      });

      final sweep = LanSweepDiscovery(client: mock);
      final result = await sweep.probe('192.168.1.42');

      expect(callCount, 1, reason: 'ClientException ne doit pas retry');
      expect(result, isNull);
      sweep.close();
    });

    test('returns null on non-200 response', () async {
      final mock = MockClient((req) async => http.Response('nope', 404));
      final sweep = LanSweepDiscovery(client: mock);
      expect(await sweep.probe('192.168.1.42'), isNull);
      sweep.close();
    });

    test('returns null when service field is missing', () async {
      final mock = MockClient(
        (req) async => http.Response('{"foo":"bar"}', 200),
      );
      final sweep = LanSweepDiscovery(client: mock);
      expect(await sweep.probe('192.168.1.42'), isNull);
      sweep.close();
    });

    test('returns null when service field is wrong', () async {
      final mock = MockClient(
        (req) async => http.Response('{"service":"other"}', 200),
      );
      final sweep = LanSweepDiscovery(client: mock);
      expect(await sweep.probe('192.168.1.42'), isNull);
      sweep.close();
    });
  });
}
