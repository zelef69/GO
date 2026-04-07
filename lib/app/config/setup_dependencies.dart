import '../../services/apk_download_service.dart';
import '../../services/apk_installer_service.dart';
import '../../services/apk_integrity_service.dart';
import '../../services/update_manifest_service.dart';
import '../../services/update_service.dart';
import 'app_config.dart';

class SetupDependencies {
  SetupDependencies._({required this.updateService});

  final UpdateService updateService;

  factory SetupDependencies.create() {
    final updateService = UpdateService(
      manifestService: UpdateManifestService(
        manifestUrl: AppConfig.updateManifestUrl,
        source: _parseUpdateManifestSource(AppConfig.updateSource),
        firestoreCollection: AppConfig.updateFirestoreCollection,
        firestoreDocument: AppConfig.updateFirestoreDocument,
        defaultAppId: AppConfig.updateAppId,
      ),
      apkDownloadService: ApkDownloadService(),
      apkIntegrityService: ApkIntegrityService(),
      apkInstallerService: ApkInstallerService(),
    );
    return SetupDependencies._(updateService: updateService);
  }
}

UpdateManifestSource _parseUpdateManifestSource(String raw) {
  final normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'manifest':
    case 'manifest_url':
    case 'url':
      return UpdateManifestSource.manifestUrl;
    case 'firestore':
      return UpdateManifestSource.firestore;
    default:
      return UpdateManifestSource.auto;
  }
}
