package mx.jale.app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var preparing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mx.jale.app/play_integrity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val projectNumber = call.argument<Number>("projectNumber")?.toLong()
                    if (projectNumber == null) {
                        result.error("INVALID_PROJECT", "Falta el número del proyecto.", null)
                    } else {
                        prepareIntegrity(projectNumber, result)
                    }
                }
                "token" -> {
                    val requestHash = call.argument<String>("requestHash")
                    val provider = tokenProvider
                    if (provider == null || requestHash.isNullOrBlank()) {
                        result.error("NOT_READY", "Play Integrity no está preparado.", null)
                    } else {
                        provider.request(
                            StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
                                .setRequestHash(requestHash)
                                .build(),
                        ).addOnSuccessListener { response -> result.success(response.token()) }
                            .addOnFailureListener { error ->
                                tokenProvider = null
                                result.error("TOKEN_FAILED", error.message, null)
                            }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepareIntegrity(projectNumber: Long, result: MethodChannel.Result) {
        if (tokenProvider != null) {
            result.success(true)
            return
        }
        if (preparing) {
            result.error("PREPARING", "Play Integrity aún se está preparando.", null)
            return
        }
        preparing = true
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
                    .setCloudProjectNumber(projectNumber)
                    .build(),
            ).addOnSuccessListener { provider ->
                preparing = false
                tokenProvider = provider
                result.success(true)
            }.addOnFailureListener { error ->
                preparing = false
                result.error("PREPARE_FAILED", error.message, null)
            }
    }
}
