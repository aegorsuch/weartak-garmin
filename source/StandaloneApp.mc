import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class StandaloneApp extends Application.AppBase {
    private var view;
    private var takClient;
    private var chatMessages = [];
    private var sensorInfo;
    private var exertionPercent as Number = 0;
    private var locationServices as Boolean = true;
    private var physiologicalAlertsEnabled as Boolean = false;
    private var batteryAlertsEnabled as Boolean = false;
    private var immersionAlertsEnabled as Boolean = false;
    private var lowPressureAlertsEnabled as Boolean = false;
    private var highPressureAlertsEnabled as Boolean = false;
    private var lowPressureThreshold as Number = 950;
    private var highPressureThreshold as Number = 2000;
    private var chatEnabled as Boolean = true;
    private var bloodhoundCompassEnabled as Boolean = true;
    private var bloodhoundProximityVibrationEnabled as Boolean = true;
    private var bloodhoundProximityRadius as Number = 50;
    private var bloodhoundProximityIntensity as String = "Single Burst";
    private var highRestingHeartRate as Number = 120;
    private var highRestingWarningLength as Number = 5;
    private var highRestingAlertLength as Number = 10;
    private var lowRestingHeartRate as Number = 40;
    private var lowRestingWarningLength as Number = 5;
    private var lowRestingAlertLength as Number = 10;
    private var highRestingWarningActive as Boolean = false;
    private var highRestingAlertActive as Boolean = false;
    private var lowRestingWarningActive as Boolean = false;
    private var lowRestingAlertActive as Boolean = false;
    private var lowPressureAlertActive as Boolean = false;
    private var highPressureAlertActive as Boolean = false;
    private var exertionWarningThreshold as Number = 80;
    private var exertionWarningLength as Number = 120;
    private var exertionAlertThreshold as Number = 90;
    private var exertionAlertLength as Number = 120;
    private var exertionWarningActive as Boolean = false;
    private var exertionAlertActive as Boolean = false;
    private var birthYear as Number = 1990;
    private var height as Number = 68;
    private var weight as Number = 155;
    private var sex as String = "Not Set";
    private var bloodType as String = "Unknown";
    private var userType as String = "N/A";
    private var allergies as Array = ["N/A"];
    private var uniformWaistSize as Number = 32;
    private var strideLength as Number = 30;
    private var uniformPantsLength as Number = 32;
    private var loadoutWeight as Number = 72;
    private var language as String = "English";

    function initialize() {
        Application.AppBase.initialize();
        takClient = new TakClient();
        takClient.incomingCotCallback = method(:onIncomingCot);
        takClient.incomingChatCallback = method(:onIncomingChat);
        var storedLocationServices = Application.Storage.getValue("locationServices");
        if (storedLocationServices != null) {
            locationServices = storedLocationServices as Boolean;
        }
        loadAlertSettings();
        applyLocationServices();
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensor));
    }

    function setLocationServices(enabled as Boolean) as Void {
        locationServices = enabled;
        Application.Storage.setValue("locationServices", enabled);
        applyLocationServices();
    }

    function isLocationServicesEnabled() as Boolean {
        return locationServices;
    }

    function getLanguage() as String {
        return language;
    }

    function setLanguage(selectedLanguage as String) as Void {
        language = selectedLanguage;
        Application.Storage.setValue("language", selectedLanguage);
    }

    function languageOptions() as Array {
        return ["English", "Arabic", "Danish", "Dutch", "French", "German", "Hebrew", "Italian", "Japanese", "Korean", "Norwegian", "Polish", "Romanian", "Russian", "Spanish", "Swedish", "Thai", "Ukrainian"];
    }

    function settingsLabel() as String {
        return navigationLabel("Settings", translatedSettings());
    }

    function devicePreferencesLabel() as String {
        return navigationLabel("Device Preferences", translatedDevicePreferences());
    }

    function languageMenuLabel() as String {
        return navigationLabel("Language", translatedLanguage());
    }

    function navigationLabel(english as String, translated as String) as String {
        return language.equals("English") ? english : translated + " (" + english + ")";
    }

    function text(key as Symbol) as String {
        if (key == :map) {
            return translated("Map", "الخريطة", "Kort", "Kaart", "Carte", "Karte", "מפה", "Mappa", "地図", "지도", "Kart", "Mapa", "Harta", "Карта", "Mapa", "Karta", "แผนที่", "Мапа");
        } else if (key == :settings) {
            return settingsLabel();
        } else if (key == :clear2525d) {
            return translated("Clear 2525D", "مسح 2525D", "Ryd 2525D", "2525D wissen", "Effacer 2525D", "2525D loschen", "נקה 2525D", "Cancella 2525D", "2525Dを消去", "2525D 지우기", "Tomm 2525D", "Wyczysc 2525D", "Sterge 2525D", "Очистить 2525D", "Borrar 2525D", "Rensa 2525D", "ล้าง 2525D", "Очистити 2525D");
        } else if (key == :environment) {
            return translated("Environment", "البيئة", "Miljo", "Omgeving", "Environnement", "Umgebung", "סביבה", "Ambiente", "環境", "환경", "Miljo", "Srodowisko", "Mediu", "Среда", "Entorno", "Miljo", "สภาพแวดล้อม", "Довкілля");
        } else if (key == :exit) {
            return translated("Exit", "خروج", "Afslut", "Afsluiten", "Quitter", "Beenden", "יציאה", "Esci", "終了", "종료", "Avslutt", "Wyjscie", "Iesire", "Выход", "Salir", "Avsluta", "ออก", "Вихід");
        } else if (key == :manualAlert) {
            return translated("Manual Alert", "تنبيه يدوي", "Manuel alarm", "Handmatig alarm", "Alerte manuelle", "Manueller Alarm", "התראה ידנית", "Avviso manuale", "手動アラート", "수동 알림", "Manuelt varsel", "Alert reczny", "Alerta manuala", "Ручное оповещение", "Alerta manual", "Manuellt larm", "แจ้งเตือนด้วยตนเอง", "Ручна тривога");
        } else if (key == :physiology) {
            return translated("Physiology", "الفسيولوجيا", "Fysiologi", "Fysiologie", "Physiologie", "Physiologie", "פיזיולוגיה", "Fisiologia", "生理", "생리", "Fysiologi", "Fizjologia", "Fiziologie", "Физиология", "Fisiologia", "Fysiologi", "สรีรวิทยา", "Фізіологія");
        } else if (key == :devicePreferences) {
            return devicePreferencesLabel();
        } else if (key == :networkPreferences) {
            return translated("Network Preferences", "تفضيلات الشبكة", "Netvaerksindstillinger", "Netwerkvoorkeuren", "Preferences reseau", "Netzwerkeinstellungen", "העדפות רשת", "Preferenze rete", "ネットワーク設定", "네트워크 설정", "Nettverksvalg", "Preferencje sieci", "Preferinte retea", "Параметры сети", "Preferencias de red", "Natverksinstallningar", "การตั้งค่าเครือข่าย", "Параметри мережі");
        } else if (key == :alertingPreferences) {
            return translated("Alerting Preferences", "تفضيلات التنبيهات", "Alarmindstillinger", "Alarmvoorkeuren", "Preferences alertes", "Alarmeinstellungen", "העדפות התראות", "Preferenze avvisi", "アラート設定", "알림 설정", "Varslingsvalg", "Preferencje alertow", "Preferinte alerte", "Параметры оповещений", "Preferencias de alertas", "Larminstallningar", "การตั้งค่าการแจ้งเตือน", "Параметри тривог");
        } else if (key == :toolPreferences) {
            return translated("Tool Preferences", "تفضيلات الأدوات", "Vaerktojsindstillinger", "Hulpmiddelvoorkeuren", "Preferences outils", "Werkzeugeinstellungen", "העדפות כלים", "Preferenze strumenti", "ツール設定", "도구 설정", "Verktoyvalg", "Preferencje narzedzi", "Preferinte unelte", "Параметры инструментов", "Preferencias de herramientas", "Verktygsinstallningar", "การตั้งค่าเครื่องมือ", "Параметри інструментів");
        } else if (key == :locationServices) {
            return translated("Location Services", "خدمات الموقع", "Placeringstjenester", "Locatieservices", "Services de localisation", "Ortungsdienste", "שירותי מיקום", "Servizi posizione", "位置情報サービス", "위치 서비스", "Posisjonstjenester", "Uslugi lokalizacji", "Servicii locatie", "Службы геолокации", "Servicios de ubicacion", "Platstjanster", "บริการตำแหน่ง", "Служби геолокації");
        } else if (key == :language) {
            return languageMenuLabel();
        } else if (key == :userMetrics) {
            return translated("My User Metrics", "قياساتي", "Mine brugerdata", "Mijn gebruikersmetingen", "Mes donnees", "Meine Benutzerdaten", "מדדי משתמש", "Metriche utente", "ユーザー指標", "사용자 지표", "Mine brukerdata", "Moje dane", "Datele mele", "Мои показатели", "Mis datos", "Mina anvandardata", "ข้อมูลผู้ใช้", "Мої показники");
        } else if (key == :physiologicalAlerts) {
            return translated("Physiological Alerts", "تنبيهات فسيولوجية", "Fysiologiske alarmer", "Fysiologische alarmen", "Alertes physiologiques", "Physiologische Alarme", "התראות פיזיולוגיות", "Avvisi fisiologici", "生理アラート", "생리 알림", "Fysiologiske varsler", "Alerty fizjologiczne", "Alerte fiziologice", "Физиологические оповещения", "Alertas fisiologicas", "Fysiologiska larm", "การแจ้งเตือนสรีรวิทยา", "Фізіологічні тривоги");
        } else if (key == :environmentalAlerts) {
            return translated("Environmental Alerts", "تنبيهات بيئية", "Miljoalarmer", "Omgevingsalarmen", "Alertes environnementales", "Umgebungsalarme", "התראות סביבה", "Avvisi ambientali", "環境アラート", "환경 알림", "Miljovarsler", "Alerty srodowiskowe", "Alerte mediu", "Оповещения среды", "Alertas ambientales", "Miljolarm", "การแจ้งเตือนสภาพแวดล้อม", "Тривоги довкілля");
        } else if (key == :batteryAlerts) {
            return translated("Battery Alerts", "تنبيهات البطارية", "Batterialarmer", "Batterijalarmen", "Alertes batterie", "Batteriealarme", "התראות סוללה", "Avvisi batteria", "バッテリーアラート", "배터리 알림", "Batterivarsler", "Alerty baterii", "Alerte baterie", "Оповещения батареи", "Alertas de bateria", "Batterilarm", "การแจ้งเตือนแบตเตอรี่", "Тривоги батареї");
        } else if (key == :immersionAlerts) {
            return translated("Immersion Alerts", "تنبيهات الغمر", "Neddykning alarmer", "Onderdompelingsalarmen", "Alertes immersion", "Immersionsalarme", "התראות טבילה", "Avvisi immersione", "浸水アラート", "침수 알림", "Nedsenkingsvarsler", "Alerty zanurzenia", "Alerte imersie", "Оповещения погружения", "Alertas de inmersion", "Nedsankningslarm", "การแจ้งเตือนการแช่น้ำ", "Тривоги занурення");
        } else if (key == :atmPressureAlerts) {
            return translated("Atm Pressure Alerts", "تنبيهات الضغط الجوي", "Lufttryk alarmer", "Luchtdrukalarmen", "Alertes pression atm", "Luftdruckalarme", "התראות לחץ אוויר", "Avvisi pressione atm", "気圧アラート", "기압 알림", "Lufttrykkvarsler", "Alerty cisnienia", "Alerte presiune", "Оповещения давления", "Alertas presion atm", "Lufttryckslarm", "การแจ้งเตือนความกดอากาศ", "Тривоги тиску");
        } else if (key == :restingHeartRateAlerts) {
            return translated("Resting Heart Rate Alerts", "تنبيهات نبض الراحة", "Hvilepuls alarmer", "Rusthartslag alarmen", "Alertes FC repos", "Ruhepulsalarme", "התראות דופק מנוחה", "Avvisi FC riposo", "安静時心拍アラート", "휴식 심박 알림", "Hvilepulsvarsler", "Alerty tetna spocz.", "Alerte puls repaus", "Оповещения пульса покоя", "Alertas FC reposo", "Vilopulslarm", "การแจ้งเตือนชีพจรพัก", "Тривоги пульсу спокою");
        } else if (key == :exertionAlerts) {
            return translated("Exertion Alerts", "تنبيهات الجهد", "Belastningsalarmer", "Inspanningsalarmen", "Alertes effort", "Belastungsalarme", "התראות מאמץ", "Avvisi sforzo", "運動負荷アラート", "운동 강도 알림", "Anstrengelsesvarsler", "Alerty wysilku", "Alerte efort", "Оповещения нагрузки", "Alertas esfuerzo", "Anstrangningslarm", "การแจ้งเตือนความพยายาม", "Тривоги навантаження");
        } else if (key == :chat) {
            return translated("Chat", "دردشة", "Chat", "Chat", "Chat", "Chat", "צ'אט", "Chat", "チャット", "채팅", "Chat", "Czat", "Chat", "Чат", "Chat", "Chatt", "แชท", "Чат");
        } else if (key == :bloodhoundCompass) {
            return "Bloodhound/Compass";
        } else if (key == :selected) {
            return translated("Selected", "محدد", "Valgt", "Geselecteerd", "Selectionne", "Ausgewahlt", "נבחר", "Selezionato", "選択済み", "선택됨", "Valgt", "Wybrane", "Selectat", "Выбрано", "Seleccionado", "Vald", "เลือกแล้ว", "Вибрано");
        } else if (key == :on) {
            return translated("On", "تشغيل", "Til", "Aan", "Active", "Ein", "פועל", "Attivo", "オン", "켜짐", "Pa", "Wl.", "Pornit", "Вкл.", "Activado", "Pa", "เปิด", "Увімкнено");
        } else if (key == :off) {
            return translated("Off", "إيقاف", "Fra", "Uit", "Desactive", "Aus", "כבוי", "Disattivo", "オフ", "꺼짐", "Av", "Wyl.", "Oprit", "Выкл.", "Desactivado", "Av", "ปิด", "Вимкнено");
        }
        return key.toString();
    }

    function translated(english as String, arabic as String, danish as String, dutch as String, french as String, german as String, hebrew as String, italian as String, japanese as String, korean as String, norwegian as String, polish as String, romanian as String, russian as String, spanish as String, swedish as String, thai as String, ukrainian as String) as String {
        if (language.equals("Arabic")) {
            return arabic;
        } else if (language.equals("Danish")) {
            return danish;
        } else if (language.equals("Dutch")) {
            return dutch;
        } else if (language.equals("French")) {
            return french;
        } else if (language.equals("German")) {
            return german;
        } else if (language.equals("Hebrew")) {
            return hebrew;
        } else if (language.equals("Italian")) {
            return italian;
        } else if (language.equals("Japanese")) {
            return japanese;
        } else if (language.equals("Korean")) {
            return korean;
        } else if (language.equals("Norwegian")) {
            return norwegian;
        } else if (language.equals("Polish")) {
            return polish;
        } else if (language.equals("Romanian")) {
            return romanian;
        } else if (language.equals("Russian")) {
            return russian;
        } else if (language.equals("Spanish")) {
            return spanish;
        } else if (language.equals("Swedish")) {
            return swedish;
        } else if (language.equals("Thai")) {
            return thai;
        } else if (language.equals("Ukrainian")) {
            return ukrainian;
        }
        return english;
    }

    function translatedSettings() as String {
        if (language.equals("Arabic")) {
            return "الإعدادات";
        } else if (language.equals("Danish")) {
            return "Indstillinger";
        } else if (language.equals("Dutch")) {
            return "Instellingen";
        } else if (language.equals("French")) {
            return "Parametres";
        } else if (language.equals("German")) {
            return "Einstellungen";
        } else if (language.equals("Hebrew")) {
            return "הגדרות";
        } else if (language.equals("Italian")) {
            return "Impostazioni";
        } else if (language.equals("Japanese")) {
            return "設定";
        } else if (language.equals("Korean")) {
            return "설정";
        } else if (language.equals("Norwegian")) {
            return "Innstillinger";
        } else if (language.equals("Polish")) {
            return "Ustawienia";
        } else if (language.equals("Romanian")) {
            return "Setari";
        } else if (language.equals("Russian")) {
            return "Настройки";
        } else if (language.equals("Spanish")) {
            return "Ajustes";
        } else if (language.equals("Swedish")) {
            return "Installningar";
        } else if (language.equals("Thai")) {
            return "การตั้งค่า";
        } else if (language.equals("Ukrainian")) {
            return "Налаштування";
        }
        return "Settings";
    }

    function translatedDevicePreferences() as String {
        if (language.equals("Arabic")) {
            return "تفضيلات الجهاز";
        } else if (language.equals("Danish")) {
            return "Enhedsindstillinger";
        } else if (language.equals("Dutch")) {
            return "Apparaatvoorkeuren";
        } else if (language.equals("French")) {
            return "Preferences appareil";
        } else if (language.equals("German")) {
            return "Gerateeinstellungen";
        } else if (language.equals("Hebrew")) {
            return "העדפות מכשיר";
        } else if (language.equals("Italian")) {
            return "Preferenze dispositivo";
        } else if (language.equals("Japanese")) {
            return "デバイス設定";
        } else if (language.equals("Korean")) {
            return "장치 설정";
        } else if (language.equals("Norwegian")) {
            return "Enhetsvalg";
        } else if (language.equals("Polish")) {
            return "Preferencje urzadzenia";
        } else if (language.equals("Romanian")) {
            return "Preferinte dispozitiv";
        } else if (language.equals("Russian")) {
            return "Параметры устройства";
        } else if (language.equals("Spanish")) {
            return "Preferencias del dispositivo";
        } else if (language.equals("Swedish")) {
            return "Enhetsinstallningar";
        } else if (language.equals("Thai")) {
            return "การตั้งค่าอุปกรณ์";
        } else if (language.equals("Ukrainian")) {
            return "Параметри пристрою";
        }
        return "Device Preferences";
    }

    function translatedLanguage() as String {
        if (language.equals("Arabic")) {
            return "اللغة";
        } else if (language.equals("Danish")) {
            return "Sprog";
        } else if (language.equals("Dutch")) {
            return "Taal";
        } else if (language.equals("French")) {
            return "Langue";
        } else if (language.equals("German")) {
            return "Sprache";
        } else if (language.equals("Hebrew")) {
            return "שפה";
        } else if (language.equals("Italian")) {
            return "Lingua";
        } else if (language.equals("Japanese")) {
            return "言語";
        } else if (language.equals("Korean")) {
            return "언어";
        } else if (language.equals("Norwegian")) {
            return "Sprak";
        } else if (language.equals("Polish")) {
            return "Jezyk";
        } else if (language.equals("Romanian")) {
            return "Limba";
        } else if (language.equals("Russian")) {
            return "Язык";
        } else if (language.equals("Spanish")) {
            return "Idioma";
        } else if (language.equals("Swedish")) {
            return "Sprak";
        } else if (language.equals("Thai")) {
            return "ภาษา";
        } else if (language.equals("Ukrainian")) {
            return "Мова";
        }
        return "Language";
    }

    function languageLabel(selectedLanguage as String) as String {
        if (selectedLanguage.equals("Arabic")) {
            return "العربية (Arabic)";
        } else if (selectedLanguage.equals("Danish")) {
            return "Dansk (Danish)";
        } else if (selectedLanguage.equals("Dutch")) {
            return "Nederlands (Dutch)";
        } else if (selectedLanguage.equals("French")) {
            return "Francais (French)";
        } else if (selectedLanguage.equals("German")) {
            return "Deutsch (German)";
        } else if (selectedLanguage.equals("Hebrew")) {
            return "עברית (Hebrew)";
        } else if (selectedLanguage.equals("Italian")) {
            return "Italiano (Italian)";
        } else if (selectedLanguage.equals("Japanese")) {
            return "日本語 (Japanese)";
        } else if (selectedLanguage.equals("Korean")) {
            return "한국어 (Korean)";
        } else if (selectedLanguage.equals("Norwegian")) {
            return "Norsk (Norwegian)";
        } else if (selectedLanguage.equals("Polish")) {
            return "Polski (Polish)";
        } else if (selectedLanguage.equals("Romanian")) {
            return "Romana (Romanian)";
        } else if (selectedLanguage.equals("Russian")) {
            return "Русский (Russian)";
        } else if (selectedLanguage.equals("Spanish")) {
            return "Espanol (Spanish)";
        } else if (selectedLanguage.equals("Swedish")) {
            return "Svenska (Swedish)";
        } else if (selectedLanguage.equals("Thai")) {
            return "ไทย (Thai)";
        } else if (selectedLanguage.equals("Ukrainian")) {
            return "Українська (Ukrainian)";
        }
        return "English (English)";
    }

    function loadAlertSettings() as Void {
        var storedValue = Application.Storage.getValue("physiologicalAlertsEnabled");
        if (storedValue != null) {
            physiologicalAlertsEnabled = storedValue as Boolean;
        }
        batteryAlertsEnabled = storedBoolean("batteryAlertsEnabled", batteryAlertsEnabled);
        immersionAlertsEnabled = storedBoolean("immersionAlertsEnabled", immersionAlertsEnabled);
        lowPressureAlertsEnabled = storedBoolean("lowPressureAlertsEnabled", lowPressureAlertsEnabled);
        highPressureAlertsEnabled = storedBoolean("highPressureAlertsEnabled", highPressureAlertsEnabled);
        lowPressureThreshold = storedNumber("lowPressureThreshold", lowPressureThreshold);
        highPressureThreshold = storedNumber("highPressureThreshold", highPressureThreshold);
        chatEnabled = storedBoolean("chatEnabled", chatEnabled);
        bloodhoundCompassEnabled = storedBoolean("bloodhoundCompassEnabled", bloodhoundCompassEnabled);
        bloodhoundProximityVibrationEnabled = storedBoolean("bloodhoundProximityVibrationEnabled", bloodhoundProximityVibrationEnabled);
        bloodhoundProximityRadius = storedNumber("bloodhoundProximityRadius", bloodhoundProximityRadius);
        bloodhoundProximityIntensity = storedString("bloodhoundProximityIntensity", bloodhoundProximityIntensity);
        highRestingHeartRate = storedNumber("highRestingHeartRate", highRestingHeartRate);
        highRestingWarningLength = storedNumber("highRestingWarningLength", highRestingWarningLength);
        highRestingAlertLength = storedNumber("highRestingAlertLength", highRestingAlertLength);
        lowRestingHeartRate = storedNumber("lowRestingHeartRate", lowRestingHeartRate);
        lowRestingWarningLength = storedNumber("lowRestingWarningLength", lowRestingWarningLength);
        lowRestingAlertLength = storedNumber("lowRestingAlertLength", lowRestingAlertLength);
        exertionWarningThreshold = storedNumber("exertionWarningThreshold", exertionWarningThreshold);
        exertionWarningLength = storedNumber("exertionWarningLength", exertionWarningLength);
        exertionAlertThreshold = storedNumber("exertionAlertThreshold", exertionAlertThreshold);
        exertionAlertLength = storedNumber("exertionAlertLength", exertionAlertLength);
        birthYear = storedNumber("birthYear", birthYear);
        height = storedNumber("height", height);
        weight = storedNumber("weight", weight);
        sex = storedString("sex", sex);
        bloodType = storedString("bloodType", bloodType);
        userType = storedString("userType", userType);
        var storedAllergies = Application.Storage.getValue("allergies");
        if (storedAllergies != null) {
            allergies = storedAllergies as Array;
        }
        uniformWaistSize = storedNumber("uniformWaistSize", uniformWaistSize);
        strideLength = storedNumber("strideLength", strideLength);
        uniformPantsLength = storedNumber("uniformPantsLength", uniformPantsLength);
        loadoutWeight = storedNumber("loadoutWeight", loadoutWeight);
        language = storedString("language", language);
    }

    function storedNumber(key as String, fallback as Number) as Number {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as Number;
    }

    function storedBoolean(key as String, fallback as Boolean) as Boolean {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as Boolean;
    }

    function storedString(key as String, fallback as String) as String {
        var storedValue = Application.Storage.getValue(key);
        return storedValue == null ? fallback : storedValue as String;
    }

    function isPhysiologicalAlertsEnabled() as Boolean {
        return physiologicalAlertsEnabled;
    }

    function setPhysiologicalAlertsEnabled(enabled as Boolean) as Void {
        physiologicalAlertsEnabled = enabled;
        Application.Storage.setValue("physiologicalAlertsEnabled", enabled);
    }

    function isBatteryAlertsEnabled() as Boolean {
        return batteryAlertsEnabled;
    }

    function setBatteryAlertsEnabled(enabled as Boolean) as Void {
        batteryAlertsEnabled = enabled;
        Application.Storage.setValue("batteryAlertsEnabled", enabled);
    }

    function isImmersionAlertsEnabled() as Boolean {
        return immersionAlertsEnabled;
    }

    function setImmersionAlertsEnabled(enabled as Boolean) as Void {
        immersionAlertsEnabled = enabled;
        Application.Storage.setValue("immersionAlertsEnabled", enabled);
    }

    function isLowPressureAlertsEnabled() as Boolean {
        return lowPressureAlertsEnabled;
    }

    function setLowPressureAlertsEnabled(enabled as Boolean) as Void {
        lowPressureAlertsEnabled = enabled;
        Application.Storage.setValue("lowPressureAlertsEnabled", enabled);
    }

    function isHighPressureAlertsEnabled() as Boolean {
        return highPressureAlertsEnabled;
    }

    function setHighPressureAlertsEnabled(enabled as Boolean) as Void {
        highPressureAlertsEnabled = enabled;
        Application.Storage.setValue("highPressureAlertsEnabled", enabled);
    }

    function isChatEnabled() as Boolean {
        return chatEnabled;
    }

    function setChatEnabled(enabled as Boolean) as Void {
        chatEnabled = enabled;
        Application.Storage.setValue("chatEnabled", enabled);
    }

    function isBloodhoundCompassEnabled() as Boolean {
        return bloodhoundCompassEnabled;
    }

    function setBloodhoundCompassEnabled(enabled as Boolean) as Void {
        bloodhoundCompassEnabled = enabled;
        Application.Storage.setValue("bloodhoundCompassEnabled", enabled);
    }

    function isBloodhoundProximityVibrationEnabled() as Boolean {
        return bloodhoundProximityVibrationEnabled;
    }

    function setBloodhoundProximityVibrationEnabled(enabled as Boolean) as Void {
        bloodhoundProximityVibrationEnabled = enabled;
        Application.Storage.setValue("bloodhoundProximityVibrationEnabled", enabled);
    }

    function getBloodhoundProximityRadius() as Number {
        return bloodhoundProximityRadius;
    }

    function setBloodhoundProximityRadius(radius as Number) as Void {
        bloodhoundProximityRadius = radius;
        Application.Storage.setValue("bloodhoundProximityRadius", radius);
    }

    function getBloodhoundProximityIntensity() as String {
        return bloodhoundProximityIntensity;
    }

    function setBloodhoundProximityIntensity(intensity as String) as Void {
        bloodhoundProximityIntensity = intensity;
        Application.Storage.setValue("bloodhoundProximityIntensity", intensity);
    }

    function getAlertSetting(setting as Symbol) as Number {
        if (setting == :highThreshold) {
            return highRestingHeartRate;
        } else if (setting == :highWarning) {
            return highRestingWarningLength;
        } else if (setting == :highAlert) {
            return highRestingAlertLength;
        } else if (setting == :lowThreshold) {
            return lowRestingHeartRate;
        } else if (setting == :lowWarning) {
            return lowRestingWarningLength;
        } else if (setting == :lowAlert) {
            return lowRestingAlertLength;
        } else if (setting == :exertionWarningThreshold) {
            return exertionWarningThreshold;
        } else if (setting == :exertionWarningLength) {
            return exertionWarningLength;
        } else if (setting == :exertionAlertThreshold) {
            return exertionAlertThreshold;
        } else if (setting == :lowPressureThreshold) {
            return lowPressureThreshold;
        } else if (setting == :highPressureThreshold) {
            return highPressureThreshold;
        }
        return exertionAlertLength;
    }

    function setAlertSetting(setting as Symbol, value as Number) as Void {
        var key = "exertionAlertLength";
        if (setting == :highThreshold) {
            highRestingHeartRate = value;
            key = "highRestingHeartRate";
        } else if (setting == :highWarning) {
            highRestingWarningLength = value;
            key = "highRestingWarningLength";
        } else if (setting == :highAlert) {
            highRestingAlertLength = value;
            key = "highRestingAlertLength";
        } else if (setting == :lowThreshold) {
            lowRestingHeartRate = value;
            key = "lowRestingHeartRate";
        } else if (setting == :lowWarning) {
            lowRestingWarningLength = value;
            key = "lowRestingWarningLength";
        } else if (setting == :lowAlert) {
            lowRestingAlertLength = value;
            key = "lowRestingAlertLength";
        } else if (setting == :exertionWarningThreshold) {
            exertionWarningThreshold = value;
            key = "exertionWarningThreshold";
        } else if (setting == :exertionWarningLength) {
            exertionWarningLength = value;
            key = "exertionWarningLength";
        } else if (setting == :exertionAlertThreshold) {
            exertionAlertThreshold = value;
            key = "exertionAlertThreshold";
        } else if (setting == :lowPressureThreshold) {
            lowPressureThreshold = value;
            key = "lowPressureThreshold";
        } else if (setting == :highPressureThreshold) {
            highPressureThreshold = value;
            key = "highPressureThreshold";
        } else {
            exertionAlertLength = value;
        }
        Application.Storage.setValue(key, value);
    }

    function getUserMetric(setting as Symbol) {
        if (setting == :birthYear) {
            return birthYear;
        } else if (setting == :height) {
            return height;
        } else if (setting == :weight) {
            return weight;
        } else if (setting == :sex) {
            return sex;
        } else if (setting == :bloodType) {
            return bloodType;
        } else if (setting == :uniformWaistSize) {
            return uniformWaistSize;
        } else if (setting == :strideLength) {
            return strideLength;
        } else if (setting == :uniformPantsLength) {
            return uniformPantsLength;
        } else if (setting == :loadoutWeight) {
            return loadoutWeight;
        }
        return userType;
    }

    function setUserMetric(setting as Symbol, value) as Void {
        var key = "userType";
        if (setting == :birthYear) {
            birthYear = value as Number;
            key = "birthYear";
        } else if (setting == :height) {
            height = value as Number;
            key = "height";
        } else if (setting == :weight) {
            weight = value as Number;
            key = "weight";
        } else if (setting == :sex) {
            sex = value as String;
            key = "sex";
        } else if (setting == :bloodType) {
            bloodType = value as String;
            key = "bloodType";
        } else if (setting == :uniformWaistSize) {
            uniformWaistSize = value as Number;
            key = "uniformWaistSize";
        } else if (setting == :strideLength) {
            strideLength = value as Number;
            key = "strideLength";
        } else if (setting == :uniformPantsLength) {
            uniformPantsLength = value as Number;
            key = "uniformPantsLength";
        } else if (setting == :loadoutWeight) {
            loadoutWeight = value as Number;
            key = "loadoutWeight";
        } else {
            userType = value as String;
        }
        Application.Storage.setValue(key, value);
    }

    function isAllergySelected(allergy as String) as Boolean {
        for (var i = 0; i < allergies.size(); i++) {
            if (allergies[i].equals(allergy)) {
                return true;
            }
        }
        return false;
    }

    function toggleAllergy(allergy as String) as Void {
        if (allergy.equals("N/A")) {
            allergies = ["N/A"];
        } else if (isAllergySelected(allergy)) {
            removeAllergy(allergy);
            if (allergies.size() == 0) {
                allergies = ["N/A"];
            }
        } else {
            removeAllergy("N/A");
            allergies.add(allergy);
        }
        Application.Storage.setValue("allergies", allergies);
    }

    function removeAllergy(allergy as String) as Void {
        for (var i = allergies.size() - 1; i >= 0; i--) {
            if (allergies[i].equals(allergy)) {
                allergies.remove(i);
            }
        }
    }

    function allergiesLabel() as String {
        return allergies.size() == 1 && isAllergySelected("N/A") ? "N/A" : allergies.size().toString() + " selected";
    }

    function applyLocationServices() as Void {
        if (locationServices) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function onStart(params) {
    }

    function onPosition(info as Toybox.Position.Info) as Void {
        if (!locationServices) {
            return;
        }
        takClient.updatePosition(info);
        if (view != null) {
            view.updatePosition(info);
        }
    }

    function onSensor(info as Sensor.Info) as Void {
        sensorInfo = info;
        exertionPercent = calculateExertionPercent(info.heartRate);
        evaluateExertionAlerts();
        evaluateRestingHeartRateAlerts();
        evaluatePressureAlerts();
        WatchUi.requestUpdate();
    }

    function evaluateRestingHeartRateAlerts() as Void {
        if (!physiologicalAlertsEnabled || sensorInfo.heartRate == null) {
            return;
        }
        var heartRate = sensorInfo.heartRate;
        if (heartRate >= highRestingHeartRate) {
            lowRestingWarningActive = false;
            lowRestingAlertActive = false;
            if (!highRestingWarningActive) {
                highRestingWarningActive = true;
                notifySensorAlert("High HR warning", highRestingWarningLength, 50);
            }
            if (!highRestingAlertActive) {
                highRestingAlertActive = true;
                queueTakAlert("High resting heart rate", heartRate);
            }
        } else if (heartRate <= lowRestingHeartRate) {
            highRestingWarningActive = false;
            highRestingAlertActive = false;
            if (!lowRestingWarningActive) {
                lowRestingWarningActive = true;
                notifySensorAlert("Low HR warning", lowRestingWarningLength, 50);
            }
            if (!lowRestingAlertActive) {
                lowRestingAlertActive = true;
                queueTakAlert("Low resting heart rate", heartRate);
            }
        } else {
            highRestingWarningActive = false;
            highRestingAlertActive = false;
            lowRestingWarningActive = false;
            lowRestingAlertActive = false;
        }
    }

    function evaluatePressureAlerts() as Void {
        if (sensorInfo.pressure == null) {
            return;
        }
        var pressureHpa = sensorInfo.pressure / 100;
        if (lowPressureAlertsEnabled && pressureHpa <= lowPressureThreshold) {
            highPressureAlertActive = false;
            if (!lowPressureAlertActive) {
                lowPressureAlertActive = true;
                notifySensorAlert("Low pressure warning", 1, 50);
                queueTakAlert("Low atmospheric pressure", pressureHpa);
            }
        } else if (highPressureAlertsEnabled && pressureHpa >= highPressureThreshold) {
            lowPressureAlertActive = false;
            if (!highPressureAlertActive) {
                highPressureAlertActive = true;
                notifySensorAlert("High pressure warning", 1, 50);
                queueTakAlert("High atmospheric pressure", pressureHpa);
            }
        } else {
            lowPressureAlertActive = false;
            highPressureAlertActive = false;
        }
    }

    function notifySensorAlert(label as String, durationMinutes as Number, intensity as Number) as Void {
        var durationMilliseconds = durationMinutes * 1000;
        if (durationMilliseconds < 250) {
            durationMilliseconds = 250;
        } else if (durationMilliseconds > 10000) {
            durationMilliseconds = 10000;
        }
        Attention.vibrate([new Attention.VibeProfile(intensity, durationMilliseconds)]);
        WatchUi.showToast(label, null);
    }

    function queueTakAlert(label as String, value as Number) as Void {
        // Full alert relay will be connected when the ATAK device channel is available.
    }

    function evaluateExertionAlerts() as Void {
        if (!physiologicalAlertsEnabled) {
            return;
        }
        if (exertionPercent >= exertionAlertThreshold) {
            if (!exertionAlertActive) {
                exertionAlertActive = true;
                exertionWarningActive = true;
                notifyExertion("Exertion alert", exertionAlertLength, 100);
            }
        } else if (exertionPercent >= exertionWarningThreshold) {
            exertionAlertActive = false;
            if (!exertionWarningActive) {
                exertionWarningActive = true;
                notifyExertion("Exertion warning", exertionWarningLength, 50);
            }
        } else {
            exertionWarningActive = false;
            exertionAlertActive = false;
        }
    }

    function notifyExertion(label as String, durationSeconds as Number, intensity as Number) as Void {
        var durationMilliseconds = durationSeconds * 1000;
        if (durationMilliseconds < 250) {
            durationMilliseconds = 250;
        } else if (durationMilliseconds > 10000) {
            durationMilliseconds = 10000;
        }
        Attention.vibrate([new Attention.VibeProfile(intensity, durationMilliseconds)]);
        WatchUi.showToast(label + " (" + exertionPercent.toNumber().toString() + "%)", null);
    }

    function calculateExertionPercent(heartRate) as Number {
        if (heartRate == null) {
            return 0;
        }
        var currentYear = Gregorian.info(Time.now(), Time.FORMAT_SHORT).year;
        var age = currentYear - birthYear;
        if (age < 0) {
            age = 0;
        }
        var predictedMaxHeartRate = 208 - (0.7 * age);
        return (heartRate / predictedMaxHeartRate) * 100;
    }

    function getExertionPercent() as Number {
        return exertionPercent;
    }

    function getSensorInfo() as Sensor.Info? {
        return sensorInfo;
    }

    function onIncomingCot(uid, latitude, longitude, type) as Void {
        getMapView().updateIncomingCot(uid, latitude, longitude, type);
    }

    function onIncomingChat(message as Dictionary) as Void {
        chatMessages.add(message);
        if (chatMessages.size() > 20) {
            chatMessages.remove(0);
        }
    }

    function getChatMessages() as Array {
        return chatMessages;
    }

    function sendChatReply(replyTo as String, text as String) as Void {
        takClient.sendChatReply(replyTo, text);
    }

    function getMapView() as StandaloneMapView {
        if (view == null) {
            view = new StandaloneMapView();
            view.setTakClient(takClient);
        }
        return view;
    }

    function getTakClient() as TakClient {
        return takClient;
    }

    function getInitialView() {
        return [buildMainMenu(self), new MainMenuDelegate(self)];
    }
}
