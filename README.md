<p align="center">
  <img src="assets/images/banner.jpg" alt="FamilyPulse Banner" width="100%" />
</p>

---

<p align="center">
  Современная кроссплатформенная система родительского контроля и семейной безопасности на базе <strong>Flutter</strong>, <strong>Kotlin</strong> и <strong>Firebase</strong>.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Kotlin-Built--in%20(2.2+)-7F52FF?logo=kotlin&logoColor=white" alt="Kotlin" />
  <img src="https://img.shields.io/badge/AGP-9.1.1-3DDC84?logo=android&logoColor=white" alt="AGP 9.1.1" />
  <img src="https://img.shields.io/badge/Gradle-9.3.1-02303A?logo=gradle&logoColor=white" alt="Gradle 9.3.1" />
  <img src="https://img.shields.io/badge/Firebase-Realtime%20%26%20Firestore-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
</p>

---

## О проекте

**FamilyPulse** (`com.familypulse.app`) — приложение для бережного контроля экранного времени, безопасности в сети и связи между родителями и детьми. Проект построен на чистом современном стеке Android (AGP 9.1.1 + Built-in Kotlin + Gradle 9.3.1) без устаревших плагинов и обходных путей.

### Основные возможности

* **Два режима работы в одном приложении:** единая кодовая база с разделением ролей при первом запуске (**Родитель** и **Ребёнок**) и быстрой привязкой устройств по коду.
* **Кастомный детский лаунчер (Home Launcher):** безопасный рабочий стол на устройстве ребёнка, отображающий только разрешённые приложения, виджеты связи и статус лимитов.
* **Контроль экранного времени и расписаний:**
  * Учёт реального времени использования приложений через Android `UsageStatsManager`.
  * Ночной режим и расписание блокировок по времени суток.
  * Мгновенное перекрытие запрещённых или исчерпавших лимит приложений через `BlockedAppActivity`.
* **Защита от обхода и удаления:**
  * Мониторинг системных окон через `AccessibilityService` (блокировка доступа к сбросу прав в системных настройках).
  * Защита от удаления приложения через `DeviceAdminReceiver`.
  * Фоновая синхронизация правил и статусов через `WorkManager` и Foreground Services.
* **Локальная DNS-фильтрация (VPN):** встроенный локальный VPN-сервис на устройстве ребёнка для фильтрации нежелательных доменов без сторонних серверов.
* **Геолокация и телеметрия:** отслеживание актуального местоположения ребёнка в реальном времени, контроль уровня заряда батареи и статуса сети.
* **Семейный чат и задачи:** встроенный обмен сообщениями и система поручений/наград.
* **Автообновление через GitHub Releases:** встроенный сервис `GitHubUpdateService` для проверки и установки новых версий APK напрямую из релизов репозитория.

---

## Технологический стек

* **UI и бизнес-логика:** Flutter (Dart), Material 3
* **Нативный Android-слой:** Kotlin (Built-in Kotlin в AGP 9.1.1), Java 17
* **Сборка:** Android Gradle Plugin `9.1.1`, Gradle Wrapper `9.3.1`
* **Бэкенд и синхронизация:** Firebase Authentication, Cloud Firestore, Firebase Cloud Messaging (FCM)
* **Android System APIs:** `UsageStatsManager`, `AccessibilityService`, `DevicePolicyManager`, `VpnService`, `WorkManager`

---