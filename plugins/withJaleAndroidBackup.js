const fs = require('fs');
const path = require('path');
const { withAndroidManifest, withDangerousMod, withProjectBuildGradle } = require('@expo/config-plugins');

const NDK_VERSION = '28.2.13676358';
const KOTLIN_VERSION = '2.1.20';

const legacyRules = `<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="database" path="." />
    <include domain="file" path="branding/" />
</full-backup-content>
`;

const modernRules = `<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <include domain="database" path="." />
        <include domain="file" path="branding/" />
    </cloud-backup>
    <device-transfer>
        <include domain="database" path="." />
        <include domain="file" path="branding/" />
    </device-transfer>
</data-extraction-rules>
`;

module.exports = function withJaleAndroidBackup(config) {
  config = withProjectBuildGradle(config, current => {
    if (!current.modResults.contents.includes('ext.ndkVersion')) {
      current.modResults.contents = current.modResults.contents.replace(
        'apply plugin: "expo-root-project"',
        `ext.ndkVersion = '${NDK_VERSION}'\napply plugin: "expo-root-project"`,
      );
    }
    if (!current.modResults.contents.includes(`kotlin-stdlib:${KOTLIN_VERSION}`)) {
      current.modResults.contents = current.modResults.contents.replace(
        'allprojects {',
        `allprojects {\n  configurations.configureEach {\n    resolutionStrategy.force 'org.jetbrains.kotlin:kotlin-stdlib:${KOTLIN_VERSION}'\n    resolutionStrategy.force 'org.jetbrains.kotlin:kotlin-stdlib-jdk7:${KOTLIN_VERSION}'\n    resolutionStrategy.force 'org.jetbrains.kotlin:kotlin-stdlib-jdk8:${KOTLIN_VERSION}'\n  }`,
      );
    }
    return current;
  });
  config = withAndroidManifest(config, current => {
    const application = current.modResults.manifest.application?.[0];
    if (application) {
      application.$['android:allowBackup'] = 'true';
      application.$['android:fullBackupContent'] = '@xml/backup_rules';
      application.$['android:dataExtractionRules'] = '@xml/data_extraction_rules';
    }
    return current;
  });
  return withDangerousMod(config, ['android', async current => {
    const directory = path.join(current.modRequest.platformProjectRoot, 'app', 'src', 'main', 'res', 'xml');
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, 'backup_rules.xml'), legacyRules);
    fs.writeFileSync(path.join(directory, 'data_extraction_rules.xml'), modernRules);
    return current;
  }]);
};
