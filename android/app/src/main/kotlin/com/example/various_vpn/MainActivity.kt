package com.example.various_vpn

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "various_vpn/status"

    /** Варианты иконки: ключ из Flutter → activity-alias в манифесте. */
    private val iconAliases = mapOf(
        "classic" to ".IconAliasClassic",
        "midnight" to ".IconAliasMidnight",
        "indigo" to ".IconAliasIndigo",
        "steel" to ".IconAliasSteel",
        "pearl" to ".IconAliasPearl",
        "lime" to ".IconAliasLime"
    )

    /**
     * Выбранный вариант иконки, который ещё не применён.
     *
     * Применять смену прямо по нажатию нельзя: приложение запущено ЧЕРЕЗ один
     * из activity-alias, и как только мы его выключаем, система закрывает
     * текущую задачу — приложение просто исчезало с экрана. Флаг DONT_KILL_APP
     * от этого не спасает: он про процесс, а не про задачу.
     *
     * Поэтому запоминаем выбор и применяем его в onStop — когда человек сам
     * ушёл с экрана. К моменту, когда он посмотрит на рабочий стол, иконка уже
     * новая, а из приложения его никто не выкидывал.
     */
    private var pendingIcon: String? = null

    override fun onStop() {
        super.onStop()
        pendingIcon?.let {
            applyIcon(it)
            pendingIcon = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Мгновенный источник правды: есть ли прямо сейчас активная
                    // VPN-сеть на уровне ОС. Переживает удаление из «недавних»
                    // (VPN-сервис sticky), не ждёт broadcast'ов плагина.
                    "vpnActive" -> result.success(isVpnActive())
                    "setAppIcon" -> {
                        val key = call.argument<String>("key") ?: "classic"
                        if (iconAliases.containsKey(key)) {
                            // НЕ применяем сразу: см. комментарий у pendingIcon.
                            pendingIcon = key
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "currentAppIcon" -> result.success(pendingIcon ?: currentIcon())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Переключает иконку приложения.
     *
     * Android не умеет менять `android:icon` на лету — вместо этого в манифесте
     * лежит по одному activity-alias на вариант, и мы включаем нужный, выключая
     * остальные. Базовая MainActivity при этом ОТКЛЮЧАЕТСЯ: иначе в лаунчере
     * окажутся два ярлыка сразу.
     *
     * Важно: включённым всегда должен остаться ровно один компонент с
     * LAUNCHER-фильтром — иначе приложение пропадёт из меню. Поэтому сначала
     * включаем новый, и только потом гасим прежние.
     */
    private fun applyIcon(key: String): Boolean {
        val target = iconAliases[key] ?: return false
        return try {
            val pm = packageManager
            val pkg = packageName
            fun set(name: String, on: Boolean) {
                pm.setComponentEnabledSetting(
                    ComponentName(pkg, "$pkg$name"),
                    if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
            set(target, true)
            for ((_, alias) in iconAliases) {
                if (alias != target) set(alias, false)
            }
            // Базовая активность-ярлык больше не нужна как точка входа.
            pm.setComponentEnabledSetting(
                ComponentName(pkg, "$pkg.MainActivity"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Какой вариант включён сейчас (для галочки в списке). */
    private fun currentIcon(): String {
        return try {
            val pm = packageManager
            for ((key, alias) in iconAliases) {
                val state = pm.getComponentEnabledSetting(
                    ComponentName(packageName, "$packageName$alias")
                )
                if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return key
            }
            "classic"
        } catch (e: Exception) {
            "classic"
        }
    }

    private fun isVpnActive(): Boolean {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(net) ?: return false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } catch (e: Exception) {
            false
        }
    }
}
