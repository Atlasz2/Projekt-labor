import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/config/app_config.dart';
import 'package:mobile_app/utils/project_filter.dart';

void main() {
  group('projectIdOf', () {
    test('hiányzó projectId az alapértelmezett települést jelenti', () {
      expect(projectIdOf(null), AppConfig.defaultProjectId);
      expect(projectIdOf(<String, dynamic>{}), AppConfig.defaultProjectId);
      expect(projectIdOf({'projectId': ''}), AppConfig.defaultProjectId);
      expect(projectIdOf({'projectId': '   '}), AppConfig.defaultProjectId);
    });

    test('beállított projectId-t adja vissza', () {
      expect(projectIdOf({'projectId': 'tapolca'}), 'tapolca');
    });
  });

  group('inActiveProject', () {
    test('a kiadás településéhez tartozó dokumentum átmegy', () {
      // Alapértelmezett build: PROJECT_ID = nagyvazsony.
      expect(inActiveProject({'projectId': AppConfig.projectId}), isTrue);
      // A jelöletlen (régi) tartalom is az alapértelmezetthez tartozik.
      expect(inActiveProject(<String, dynamic>{}), isTrue);
    });

    test('másik település tartalma kimarad', () {
      expect(inActiveProject({'projectId': 'masik-telepules'}), isFalse);
    });
  });
}
