@Tags(['integration'])
// ignore_for_file: prefer_const_constructors
import 'package:test/test.dart';

// Add this import for UuidGenerator
import '../../lib/src/utils/uuid_generator.dart';

// Simple test to verify core functionality without Flutter dependencies
import '../../lib/src/commands/command.dart';
import '../../lib/src/commands/response.dart';
import '../../lib/src/commands/command_correlator.dart';

void main() {
  group('Basic CommandCorrelator Integration Tests', () {
    test('UUIDv4 generation works correctly', () {
      final uuid1 = UuidGenerator.generate();
      final uuid2 = UuidGenerator.generate();

      expect(uuid1.length, equals(36));
      expect(uuid2.length, equals(36));
      expect(uuid1, isNot(equals(uuid2)));
      expect(UuidGenerator.isValidUuid(uuid1), isTrue);
      expect(UuidGenerator.isValidUuid(uuid2), isTrue);
    });

    test('Command serialization and deserialization works', () {
      final command = Command(
        id: UuidGenerator.generate(),
        op: 'GET',
        key: 'test-key',
      );

      final jsonString = command.toJsonString();
      final decoded = Command.fromJsonString(jsonString);

      expect(decoded.id, equals(command.id));
      expect(decoded.op, equals(command.op));
      expect(decoded.key, equals(command.key));
    });

    test('Response serialization and deserialization works', () {
      final response = Response.ok(id: 'test-id', value: 'test-value');

      final jsonString = response.toJsonString();
      final decoded = Response.fromJsonString(jsonString);

      expect(decoded.id, equals(response.id));
      expect(decoded.status, equals(response.status));
      expect(decoded.value, equals(response.value));
    });

    test('CommandCorrelator payload size validation works', () async {
      final correlator = CommandCorrelator(publishCommand: (payload) async {});

      // Large payload should be rejected
      final largeValue = 'x' * (600 * 1024); // 600 KiB
      final command = Command(
        id: 'test-large',
        op: 'SET',
        key: 'test',
        value: largeValue,
      );

      final response = await correlator.send(command);
      expect(response.errorCode, equals(ErrorCode.payloadTooLarge));

      correlator.dispose();
    });

    test('CommandCorrelator generates UUID when ID is empty', () async {
      final List<String> publishedPayloads = [];
      final correlator = CommandCorrelator(
        publishCommand: (payload) async {
          publishedPayloads.add(payload);
        },
      );

      final command = Command(id: '', op: 'GET', key: 'test');

      final futureResponse = correlator.send(command);

      // Check that a command was published
      expect(publishedPayloads.length, equals(1));

      // Parse the published command and check it has a valid UUID
      final publishedCommand = Command.fromJsonString(publishedPayloads.first);
      expect(publishedCommand.id.length, equals(36));
      expect(UuidGenerator.isValidUuid(publishedCommand.id), isTrue);

      // Send a response to complete the request
      final response = Response.ok(
        id: publishedCommand.id,
        value: 'test-result',
      );
      correlator.onResponse(response.toJsonString());

      final actualResponse = await futureResponse;
      expect(actualResponse.isSuccess, isTrue);
      expect(actualResponse.value, equals('test-result'));

      correlator.dispose();
    });

    test('CommandCorrelator handles timeouts correctly', () async {
      final correlator = CommandCorrelator(publishCommand: (payload) async {});

      final command = Command(id: 'timeout-test', op: 'GET', key: 'test');

      // Start the request but don't send a response
      final futureResponse = correlator.send(command);

      // Wait a short time (in a real scenario, this would be longer)
      await Future.delayed(Duration(milliseconds: 50));

      // The response should eventually timeout
      final response = await futureResponse.timeout(Duration(seconds: 15));
      expect(response.errorCode, equals(ErrorCode.timeout));

      correlator.dispose();
    });

    test('CommandCorrelator deduplication cache works', () async {
      final List<String> publishedPayloads = [];
      final correlator = CommandCorrelator(
        publishCommand: (payload) async {
          publishedPayloads.add(payload);
        },
      );

      final command = Command(id: 'dedup-test', op: 'GET', key: 'test');

      // Send first request
      final future1 = correlator.send(command);
      expect(publishedPayloads.length, equals(1));

      // Complete first request
      correlator.onResponse(
        Response.ok(id: 'dedup-test', value: 'cached-value').toJsonString(),
      );
      final response1 = await future1;
      expect(response1.value, equals('cached-value'));

      // Send same request again - should get cached response without publishing
      final response2 = await correlator.send(command);
      expect(response2.isIdempotentReplay, isTrue);
      expect(response2.value, equals('cached-value'));
      expect(publishedPayloads.length, equals(1)); // Still only one publish

      correlator.dispose();
    });
  });
}
