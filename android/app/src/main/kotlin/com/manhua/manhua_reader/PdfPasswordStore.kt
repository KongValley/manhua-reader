package com.manhua.manhua_reader

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class PdfPasswordStore private constructor(private val context: Context) {
    // Android backup and device transfer exclude noBackupFilesDir.
    // Android 备份与设备迁移会排除 noBackupFilesDir。
    private val directory: File
        get() = File(checkNotNull(context.noBackupFilesDir), "pdf_passwords")

    private fun fileFor(key: String): AtomicFile {
        val name = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return AtomicFile(File(directory, name))
    }

    private fun secretKey(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null || !create) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private fun read(file: AtomicFile, key: String): String? {
        val data = try {
            file.readFully()
        } catch (error: FileNotFoundException) {
            if (file.baseFile.exists()) throw error
            return null
        }
        val secret = secretKey(create = false) ?: return null
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, data, 0, IV_BYTES))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val plaintext = cipher.doFinal(data, IV_BYTES, data.size - IV_BYTES)
        try {
            return plaintext.toString(Charsets.UTF_8)
        } finally {
            plaintext.fill(0)
        }
    }

    private fun contains(file: AtomicFile): Boolean = try {
        file.openRead().use { true }
    } catch (error: FileNotFoundException) {
        if (file.baseFile.exists()) throw error
        false
    }

    private fun write(file: AtomicFile, key: String, password: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, checkNotNull(secretKey(create = true)))
        check(cipher.iv.size == IV_BYTES)
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val plaintext = password.toByteArray(Charsets.UTF_8)
        val encrypted = try {
            cipher.doFinal(plaintext)
        } finally {
            plaintext.fill(0)
        }
        val stream = file.startWrite()
        try {
            stream.write(cipher.iv)
            stream.write(encrypted)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "manhua.pdf_password_store.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12

        fun register(context: Context, messenger: BinaryMessenger) {
            val store = PdfPasswordStore(context)
            val channel = MethodChannel(
                messenger,
                "manhua/pdf_password_store",
                StandardMethodCodec.INSTANCE,
                messenger.makeBackgroundTaskQueue(),
            )
            channel.setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key")
                    val password = call.argument<String>("password")
                    if (key.isNullOrEmpty()) {
                        result.error("bad_args", "Missing credential key", null)
                        return@setMethodCallHandler
                    }
                    val file = store.fileFor(key)
                    when (call.method) {
                        "contains" -> result.success(store.contains(file))
                        "read" -> result.success(store.read(file, key))
                        "write" -> {
                            require(!password.isNullOrEmpty())
                            store.write(file, key, password)
                            result.success(null)
                        }
                        "delete" -> {
                            if (password == null || password == store.read(file, key)) {
                                file.delete()
                                check(!store.contains(file))
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("pdf_password_store", "Secure storage is unavailable", null)
                }
            }
        }
    }
}
