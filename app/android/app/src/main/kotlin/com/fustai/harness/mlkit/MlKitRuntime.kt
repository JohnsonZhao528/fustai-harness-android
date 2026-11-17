package com.fustai.harness.mlkit

import android.content.Context
import com.google.mlkit.common.MlKit

/** Called only when admitting an enabled local OCR job. */
internal object MlKitRuntime {
    private val initialization = MlKitInitialization()

    fun initialize(context: Context) {
        initialization.ensureInitialized { MlKit.initialize(context.applicationContext) }
    }
}
