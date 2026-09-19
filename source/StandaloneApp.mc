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
        return ["English", "Arabic", "Bulgarian", "Croatian", "Czech", "Danish", "Dutch", "Estonian", "Finnish", "French", "German", "Greek", "Hebrew", "Hungarian", "Indonesian", "Italian", "Japanese", "Korean", "Latvian", "Lithuanian", "Norwegian", "Polish", "Portuguese", "Romanian", "Russian", "Slovak", "Slovenian", "Spanish", "Swedish", "Thai", "Turkish", "Ukrainian", "Vietnamese"];
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
        var extra = translatedExtra(key);
        if (!extra.equals("")) {
            return extra;
        }
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
        } else if (key == :clearManualAlert) {
            return translated("Clear Manual Alert", "مسح التنبيه اليدوي", "Ryd manuel alarm", "Handmatig alarm wissen", "Effacer l'alerte manuelle", "Manuellen Alarm loschen", "נקה התראה ידנית", "Cancella avviso manuale", "手動アラートを消去", "수동 알림 지우기", "Fjern manuelt varsel", "Wyczysc alert reczny", "Sterge alerta manuala", "Очистить ручное оповещение", "Borrar alerta manual", "Rensa manuellt larm", "ล้างการแจ้งเตือนด้วยตนเอง", "Очистити ручну тривогу");
        } else if (key == :gateRunner) {
            return translated("Gate Runner", "عداء البوابة", "Portlob", "Gate runner", "Coureur de portail", "Torlaeufer", "רץ שער", "Corridore cancello", "ゲートランナー", "게이트 러너", "Portlop", "Biegacz bramy", "Alergator poarta", "Бегун у ворот", "Corredor de puerta", "Grindlopare", "นักวิ่งประตู", "Бігун біля воріт");
        } else if (key == :gunshot) {
            return translated("Gunshot", "إطلاق نار", "Skud", "Schot", "Coup de feu", "Schuss", "יריה", "Sparo", "銃声", "총성", "Skudd", "Strzal", "Impuscatura", "Выстрел", "Disparo", "Skott", "เสียงปืน", "Постріл");
        } else if (key == :gunshotInjury) {
            return translated("Gunshot Injury", "إصابة بطلق ناري", "Skudsar", "Schotwond", "Blessure par balle", "Schussverletzung", "פציעת ירי", "Ferita da arma da fuoco", "銃創", "총상", "Skuddsar", "Rana postrzalowa", "Ranire prin impuscare", "Огнестрельное ранение", "Herida de bala", "Skottskada", "บาดเจ็บจากกระสุน", "Вогнепальне поранення");
        } else if (key == :injury) {
            return translated("Injury", "إصابة", "Skade", "Letsel", "Blessure", "Verletzung", "פציעה", "Lesione", "負傷", "부상", "Skade", "Uraz", "Ranire", "Травма", "Lesion", "Skada", "การบาดเจ็บ", "Поранення");
        } else if (key == :uas) {
            return translated("UAS", "طائرة بدون طيار", "UAS", "UAS", "UAS", "UAS", "כלי טיס בלתי מאויש", "UAS", "UAS", "UAS", "UAS", "UAS", "UAS", "БПЛА", "UAS", "UAS", "UAS", "БпЛА");
        } else if (key == :vehicle) {
            return translated("Vehicle", "مركبة", "Koretoj", "Voertuig", "Vehicule", "Fahrzeug", "רכב", "Veicolo", "車両", "차량", "Kjoretoy", "Pojazd", "Vehicul", "Транспорт", "Vehiculo", "Fordon", "ยานพาหนะ", "Транспорт");
        } else if (key == :pointTitle) {
            return translated("2525D Point", "نقطة 2525D", "2525D punkt", "2525D-punt", "Point 2525D", "2525D-Punkt", "נקודת 2525D", "Punto 2525D", "2525Dポイント", "2525D 포인트", "2525D-punkt", "Punkt 2525D", "Punct 2525D", "Точка 2525D", "Punto 2525D", "2525D-punkt", "จุด 2525D", "Точка 2525D");
        } else if (key == :bloodhound) {
            return translated("Bloodhound", "تتبع الهدف", "Sporing", "Doel volgen", "Pistage", "Zielverfolgung", "מעקב יעד", "Tracciamento", "目標追跡", "목표 추적", "Sporing", "Sledzenie celu", "Urmarire tinta", "Отслеживание цели", "Seguimiento", "Malspårning", "ติดตามเป้าหมาย", "Відстеження цілі");
        } else if (key == :stopBloodhound) {
            return translated("Stop Bloodhound", "إيقاف التتبع", "Stop sporing", "Doelvolgen stoppen", "Arreter pistage", "Zielverfolgung stoppen", "עצור מעקב", "Ferma tracciamento", "目標追跡停止", "목표 추적 중지", "Stopp sporing", "Zatrzymaj sledzenie", "Opreste urmarirea", "Остановить отслеживание", "Detener seguimiento", "Stoppa malspårning", "หยุดติดตาม", "Зупинити відстеження");
        } else if (key == :coordinates) {
            return translated("Coordinates", "الإحداثيات", "Koordinater", "Coordinaten", "Coordonnees", "Koordinaten", "קואורדינטות", "Coordinate", "座標", "좌표", "Koordinater", "Wspolrzedne", "Coordonate", "Координаты", "Coordenadas", "Koordinater", "พิกัด", "Координати");
        } else if (key == :latLon) {
            return "Lat/Lon";
        } else if (key == :mgrs) {
            return "MGRS";
        } else if (key == :setTitle) {
            return translated("Set Title", "تعيين العنوان", "Saet titel", "Titel instellen", "Definir titre", "Titel setzen", "הגדר כותרת", "Imposta titolo", "タイトル設定", "제목 설정", "Angi tittel", "Ustaw tytul", "Seteaza titlu", "Установить заголовок", "Establecer titulo", "Ange titel", "ตั้งชื่อ", "Встановити назву");
        } else if (key == :setRemark) {
            return translated("Set Remark", "تعيين الملاحظة", "Saet bemaerkning", "Opmerking instellen", "Definir remarque", "Bemerkung setzen", "הגדר הערה", "Imposta nota", "備考設定", "비고 설정", "Angi merknad", "Ustaw uwage", "Seteaza nota", "Установить примечание", "Establecer nota", "Ange kommentar", "ตั้งหมายเหตุ", "Встановити примітку");
        } else if (key == :setType) {
            return translated("Set Type", "تعيين النوع", "Saet type", "Type instellen", "Definir type", "Typ setzen", "הגדר סוג", "Imposta tipo", "種類設定", "유형 설정", "Angi type", "Ustaw typ", "Seteaza tip", "Установить тип", "Establecer tipo", "Ange typ", "ตั้งประเภท", "Встановити тип");
        } else if (key == :delete) {
            return translated("Delete", "حذف", "Slet", "Verwijderen", "Supprimer", "Loschen", "מחק", "Elimina", "削除", "삭제", "Slett", "Usun", "Sterge", "Удалить", "Eliminar", "Ta bort", "ลบ", "Видалити");
        } else if (key == :self) {
            return translated("Self", "الذات", "Egen", "Zelf", "Soi", "Selbst", "עצמי", "Se stessi", "自分", "자기 위치", "Egen", "Wlasna pozycja", "Pozitia proprie", "Свое положение", "Propio", "Egen position", "ตัวเอง", "Власна позиція");
        } else if (key == :proximity) {
            return translated("Bloodhound proximity", "اقتراب الهدف", "Naerhed til mal", "Doelnabijheid", "Proximite de la cible", "Zielnaehe", "קרבה ליעד", "Prossimita obiettivo", "目標接近", "목표 근접", "Nærhet til mål", "Bliskosc celu", "Apropiere tinta", "Близость цели", "Proximidad al objetivo", "Närhet till mål", "ความใกล้เป้าหมาย", "Близькість цілі");
        } else if (key == :cancelBloodhound) {
            return text(:stopBloodhound);
        } else if (key == :takConnect) { return "ATAK Connect";
        } else if (key == :myUserMetrics) { return "My User Metrics";
        } else if (key == :medicalProfile) { return "Medical Profile (BATDOK)";
        } else if (key == :gaitTracking) { return "Gait Tracking";
        } else if (key == :birthYear) { return "Birth Year";
        } else if (key == :height) { return "Height";
        } else if (key == :weight) { return "Weight";
        } else if (key == :sex) { return "Sex";
        } else if (key == :bloodType) { return "Blood Type";
        } else if (key == :allergies) { return "Allergies";
        } else if (key == :userType) { return "User Type";
        } else if (key == :uniformWaistSize) { return "Uniform Waist Size";
        } else if (key == :strideLength) { return "Stride Length";
        } else if (key == :uniformPantsLength) { return "Uniform Pants Length";
        } else if (key == :loadoutWeight) { return "Loadout Weight";
        } else if (key == :proximityVibration) { return "Bloodhound Proximity Vibration";
        } else if (key == :proximityRadius) { return "Bloodhound Proximity Radius";
        } else if (key == :proximityIntensity) { return "Bloodhound Proximity Intensity";
        } else if (key == :allergyEnabled) { return "Enabled";
        } else if (key == :allergyDisabled) { return "Disabled";
        } else if (key == :oldPointsCleared) {
            return translated("Old points cleared", "تم مسح النقاط القديمة", "Gamle punkter ryddet", "Oude punten gewist", "Anciens points effaces", "Alte Punkte geloscht", "נקודות ישנות נוקו", "Vecchi punti cancellati", "古いポイントを消去しました", "이전 포인트 삭제됨", "Gamle punkter fjernet", "Stare punkty wyczyszczone", "Punctele vechi au fost sterse", "Старые точки очищены", "Puntos antiguos borrados", "Gamla punkter rensade", "ล้างจุดเก่าแล้ว", "Старі точки очищено");
        } else if (key == :active) {
            return translated("Active", "نشط", "Aktiv", "Actief", "Actif", "Aktiv", "פעיל", "Attivo", "アクティブ", "활성", "Aktiv", "Aktywny", "Activ", "Активен", "Activo", "Aktiv", "ใช้งาน", "Активний");
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
            return translated("Navigation", "الملاحة", "Navigation", "Navigatie", "Navigation", "Navigation", "ניווט", "Navigazione", "ナビゲーション", "내비게이션", "Navigasjon", "Nawigacja", "Navigatie", "Навигация", "Navegacion", "Navigering", "การนำทาง", "Навігація");
        } else if (key == :clearPointsMain) {
            return translated("Clear 2525D Points", "مسح نقاط 2525D", "Ryd 2525D punkter", "2525D punten wissen", "Effacer les points 2525D", "2525D Punkte loschen", "נקה נקודות 2525D", "Cancella punti 2525D", "2525Dポイントを消去", "2525D 포인트 지우기", "Tom 2525D-punkter", "Wyczysc punkty 2525D", "Sterge punctele 2525D", "Очистить точки 2525D", "Borrar puntos 2525D", "Rensa 2525D-punkter", "ล้างจุด 2525D", "Очистити точки 2525D");
        } else if (key == :dropPoint) {
            return translated("Drop 2525D Point", "إسقاط نقطة 2525D", "Drop 2525D punkt", "2525D-punt plaatsen", "Deposer un point 2525D", "2525D-Punkt setzen", "הנח נקודת 2525D", "Inserisci punto 2525D", "2525Dポイントを配置", "2525D 포인트 놓기", "Slipp 2525D-punkt", "Upusc punkt 2525D", "Plaseaza punct 2525D", "Добавить точку 2525D", "Soltar punto 2525D", "Slapp 2525D-punkt", "วางจุด 2525D", "Додати точку 2525D");
        } else if (key == :clearPointsPrompt) {
            return translated("Clear app points?", "مسح نقاط التطبيق؟", "Ryd app-punkter?", "App-punten wissen?", "Effacer les points de l'application ?", "App-Punkte loschen?", "לנקות נקודות אפליקציה?", "Cancellare i punti dell'app?", "アプリのポイントを消去しますか？", "앱 포인트를 지울까요?", "Slette app-punkter?", "Wyczyscic punkty aplikacji?", "Stergeti punctele aplicatiei?", "Очистить точки приложения?", "¿Borrar puntos de la aplicacion?", "Rensa app-punkter?", "ล้างจุดของแอปไหม?", "Очистити точки застосунку?");
        } else if (key == :clearPointsAction) {
            return text(:clearPointsMain);
        } else if (key == :pointDropped) {
            return translated("2525D point dropped", "تم إسقاط نقطة 2525D", "2525D-punkt droppet", "2525D-punt geplaatst", "Point 2525D depose", "2525D-Punkt gesetzt", "נקודת 2525D הונחה", "Punto 2525D inserito", "2525Dポイントを配置しました", "2525D 포인트가 놓였습니다", "2525D-punkt droppet", "Upuszczono punkt 2525D", "Punct 2525D plasat", "Точка 2525D добавлена", "Punto 2525D colocado", "2525D-punkt placerad", "วางจุด 2525D แล้ว", "Точку 2525D додано");
        } else if (key == :locationUnavailable) {
            return translated("Location unavailable", "الموقع غير متاح", "Placering utilgaengelig", "Locatie niet beschikbaar", "Position indisponible", "Standort nicht verfugbar", "המיקום אינו זמין", "Posizione non disponibile", "位置情報を利用できません", "위치를 사용할 수 없음", "Posisjon utilgjengelig", "Lokalizacja niedostepna", "Locatia indisponibila", "Местоположение недоступно", "Ubicacion no disponible", "Plats ej tillganglig", "ไม่พบตำแหน่ง", "Місцезнаходження недоступне");
        } else if (key == :cancel) {
            return translated("Cancel", "إلغاء", "Annuller", "Annuleren", "Annuler", "Abbrechen", "ביטול", "Annulla", "キャンセル", "취소", "Avbryt", "Anuluj", "Anuleaza", "Отмена", "Cancelar", "Avbryt", "ยกเลิก", "Скасувати");
        } else if (key == :atmPressureTitle) {
            return text(:atmPressureAlerts);
        } else if (key == :lowPressureAlert) {
            return translated("Low Pressure Alert", "تنبيه ضغط منخفض", "Lavtryk alarm", "Laagdrukalarm", "Alerte basse pression", "Alarm niedriger Druck", "התראת לחץ נמוך", "Avviso bassa pressione", "低圧アラート", "저압 알림", "Lavtrykksvarsel", "Alert niskiego cisnienia", "Alerta presiune scazuta", "Оповещение низкого давления", "Alerta de baja presion", "Lagt trycklarm", "การแจ้งเตือนความดันต่ำ", "Тривога низького тиску");
        } else if (key == :highPressureAlert) {
            return translated("High Pressure Alert", "تنبيه ضغط مرتفع", "Hojtryk alarm", "Hogedrukalarm", "Alerte haute pression", "Alarm hoher Druck", "התראת לחץ גבוה", "Avviso alta pressione", "高圧アラート", "고압 알림", "Hoyttrykksvarsel", "Alert wysokiego cisnienia", "Alerta presiune ridicata", "Оповещение высокого давления", "Alerta de alta presion", "Hogt trycklarm", "การแจ้งเตือนความดันสูง", "Тривога високого тиску");
        } else if (key == :pressureThreshold) {
            return translated("Pressure Threshold", "حد الضغط", "Trykterskel", "Drukdrempel", "Seuil de pression", "Druckschwelle", "סף לחץ", "Soglia pressione", "圧力しきい値", "압력 임계값", "Trykkterskel", "Prog cisnienia", "Prag presiune", "Порог давления", "Umbral de presion", "Trycktröskel", "เกณฑ์ความดัน", "Поріг тиску");
        } else if (key == :restingHeartRateTitle) {
            return text(:restingHeartRateAlerts);
        } else if (key == :highRestingHeartRate) {
            return translated("High Resting Heart Rate", "معدل نبض راحة مرتفع", "Hoj hvilepuls", "Hoge rusthartslag", "Frequence cardiaque de repos elevee", "Hoher Ruhepuls", "דופק מנוחה גבוה", "Frequenza cardiaca a riposo alta", "高安静時心拍", "높은 휴식 심박", "Hoy hvilepuls", "Wysokie tetno spoczynkowe", "Puls de repaus ridicat", "Высокий пульс покоя", "Frecuencia cardiaca en reposo alta", "Hog vilopuls", "ชีพจรพักสูง", "Високий пульс спокою");
        } else if (key == :lowRestingHeartRate) {
            return translated("Low Resting Heart Rate", "معدل نبض راحة منخفض", "Lav hvilepuls", "Lage rusthartslag", "Frequence cardiaque de repos basse", "Niedriger Ruhepuls", "דופק מנוחה נמוך", "Frequenza cardiaca a riposo bassa", "低安静時心拍", "낮은 휴식 심박", "Lav hvilepuls", "Niskie tetno spoczynkowe", "Puls de repaus scazut", "Низкий пульс покоя", "Frecuencia cardiaca en reposo baja", "Lag vilopuls", "ชีพจรพักต่ำ", "Низький пульс спокою");
        } else if (key == :warningLength) {
            return translated("Warning Length", "مدة التحذير", "Advarselslaengde", "Waarschuwingsduur", "Duree avertissement", "Warnzeit", "משך אזהרה", "Durata avviso", "警告時間", "경고 시간", "Varslingslengde", "Dlugosc ostrzezenia", "Durata avertizarii", "Длительность предупреждения", "Duracion de alerta", "Varningslangd", "ระยะเวลาแจ้งเตือน", "Тривалість попередження");
        } else if (key == :alertLength) {
            return translated("Alert Length", "مدة التنبيه", "Alarmlaengde", "Alarmduur", "Duree alerte", "Alarmdauer", "משך התראה", "Durata avviso", "アラート時間", "알림 시간", "Varslingslengde", "Dlugosc alertu", "Durata alertei", "Длительность оповещения", "Duracion de alerta", "Larmlangd", "ระยะเวลาแจ้งเตือน", "Тривалість тривоги");
        } else if (key == :exertionTitle) {
            return text(:exertionAlerts);
        } else if (key == :warningThreshold) {
            return translated("Warning Threshold", "حد التحذير", "Advarselsterskel", "Waarschuwingsdrempel", "Seuil avertissement", "Warnschwelle", "סף אזהרה", "Soglia avviso", "警告しきい値", "경고 임계값", "Varselsterskel", "Prog ostrzezenia", "Prag avertizare", "Порог предупреждения", "Umbral de alerta", "Varningströskel", "เกณฑ์แจ้งเตือน", "Поріг попередження");
        } else if (key == :alertThreshold) {
            return translated("Alert Threshold", "حد التنبيه", "Alarmterskel", "Alarmdrempel", "Seuil alerte", "Alarmschwelle", "סף התראה", "Soglia allarme", "アラートしきい値", "알림 임계값", "Varselsterskel", "Prog alertu", "Prag alerta", "Порог оповещения", "Umbral de alerta", "Larmtröskel", "เกณฑ์แจ้งเตือน", "Поріг тривоги");
        } else if (key == :selected) {
            return translated("Selected", "محدد", "Valgt", "Geselecteerd", "Selectionne", "Ausgewahlt", "נבחר", "Selezionato", "選択済み", "선택됨", "Valgt", "Wybrane", "Selectat", "Выбрано", "Seleccionado", "Vald", "เลือกแล้ว", "Вибрано");
        } else if (key == :on) {
            return translated("On", "تشغيل", "Til", "Aan", "Active", "Ein", "פועל", "Attivo", "オン", "켜짐", "Pa", "Wl.", "Pornit", "Вкл.", "Activado", "Pa", "เปิด", "Увімкнено");
        } else if (key == :off) {
            return translated("Off", "إيقاف", "Fra", "Uit", "Desactive", "Aus", "כבוי", "Disattivo", "オフ", "꺼짐", "Av", "Wyl.", "Oprit", "Выкл.", "Desactivado", "Av", "ปิด", "Вимкнено");
        } else if (key == :altitude) {
            return translated("Altitude", "الارتفاع", "Hojde", "Hoogte", "Altitude", "Hoehe", "גובה", "Altitudine", "高度", "고도", "Hoyde", "Wysokosc", "Altitudine", "Высота", "Altitud", "Hojd", "ความสูง", "Висота");
        } else if (key == :pressure) {
            return translated("Pressure", "الضغط", "Tryk", "Druk", "Pression", "Druck", "לחץ", "Pressione", "気圧", "기압", "Trykk", "Cisnienie", "Presiune", "Давление", "Presion", "Tryck", "ความกดอากาศ", "Тиск");
        } else if (key == :temperature) {
            return translated("Temperature", "درجة الحرارة", "Temperatur", "Temperatuur", "Temperature", "Temperatur", "טמפרטורה", "Temperatura", "温度", "온도", "Temperatur", "Temperatura", "Temperatura", "Температура", "Temperatura", "Temperatur", "อุณหภูมิ", "Температура");
        } else if (key == :physiologyView) {
            return translated("Physiology", "الفسيولوجيا", "Fysiologi", "Fysiologie", "Physiologie", "Physiologie", "פיזיולוגיה", "Fisiologia", "生理", "생리", "Fysiologi", "Fizjologia", "Fiziologie", "Физиология", "Fisiologia", "Fysiologi", "สรีรวิทยา", "Фізіологія");
        } else if (key == :exertion) {
            return translated("Exertion", "الجهد", "Belastning", "Inspanning", "Effort", "Belastung", "מאמץ", "Sforzo", "運動負荷", "운동 강도", "Anstrengelse", "Wysilek", "Efort", "Нагрузка", "Esfuerzo", "Anstrangning", "ความพยายาม", "Навантаження");
        } else if (key == :heartRate) {
            return translated("Heart Rate", "معدل ضربات القلب", "Puls", "Hartslag", "Frequence cardiaque", "Herzfrequenz", "דופק", "Frequenza cardiaca", "心拍数", "심박수", "Puls", "Tetno", "Puls", "Пульс", "Frecuencia cardiaca", "Puls", "อัตราการเต้นของหัวใจ", "Частота серця");
        } else if (key == :unavailable) {
            return translated("Unavailable", "غير متاح", "Ikke tilgaengelig", "Niet beschikbaar", "Indisponible", "Nicht verfugbar", "לא זמין", "Non disponibile", "利用不可", "사용할 수 없음", "Utilgjengelig", "Niedostepne", "Indisponibil", "Недоступно", "No disponible", "Inte tillganglig", "ไม่พร้อมใช้งาน", "Недоступно");
        }
        return key.toString();
    }

    function translatedExtra(key as Symbol) as String {
        if (language.equals("Bulgarian")) {
            return requestedLanguageText(key, "Карта", "Изчистване 2525D", "Среда", "Изход", "Ръчно предупреждение", "Физиология", "Мрежови настройки", "Настройки за предупреждения", "Настройки на инструменти", "Навигация", "Отказ", "Включено", "Изключено");
        } else if (language.equals("Croatian")) {
            return requestedLanguageText(key, "Karta", "Obrisi 2525D", "Okolis", "Izlaz", "Rucno upozorenje", "Fiziologija", "Mrezne postavke", "Postavke upozorenja", "Postavke alata", "Navigacija", "Odustani", "Ukljuceno", "Iskljuceno");
        } else if (language.equals("Estonian")) {
            return requestedLanguageText(key, "Kaart", "Kustuta 2525D", "Keskkond", "Valju", "Käsitsi hoiatus", "Füsioloogia", "Vorgu seaded", "Hoiatuste seaded", "Tooriistade seaded", "Navigeerimine", "Loobu", "Sees", "Valjas");
        } else if (language.equals("Hungarian")) {
            return requestedLanguageText(key, "Térkép", "2525D törlése", "Környezet", "Kilépés", "Kézi riasztás", "Élettan", "Hálózati beállítások", "Riasztási beállítások", "Eszközbeállítások", "Navigáció", "Mégse", "Be", "Ki");
        } else if (language.equals("Lithuanian")) {
            return requestedLanguageText(key, "Zemelapis", "Istrinti 2525D", "Aplinka", "Iseiti", "Rankinis ispejimas", "Fiziologija", "Tinklo nustatymai", "Ispejimu nustatymai", "Irenginiu nustatymai", "Navigacija", "Atsaukti", "Ijungta", "Isjungta");
        } else if (language.equals("Slovak")) {
            return requestedLanguageText(key, "Mapa", "Vymazat 2525D", "Prostredie", "Koniec", "Rucne upozornenie", "Fyziologia", "Nastavenia siete", "Nastavenia upozorneni", "Nastavenia nastrojov", "Navigacia", "Zrusit", "Zapnute", "Vypnute");
        } else if (language.equals("Slovenian")) {
            return requestedLanguageText(key, "Zemljevid", "Izbrisi 2525D", "Okolje", "Izhod", "Rocno opozorilo", "Fiziologija", "Omrezne nastavitve", "Nastavitve opozoril", "Nastavitve orodij", "Navigacija", "Preklici", "Vklopljeno", "Izklopljeno");
        } else if (language.equals("Turkish")) {
            return requestedLanguageText(key, "Harita", "2525D temizle", "Cevre", "Cikis", "Manuel uyari", "Fizyoloji", "Ag ayarlari", "Uyari ayarlari", "Arac ayarlari", "Gezinme", "Iptal", "Acik", "Kapali");
        } else if (language.equals("Vietnamese")) {
            return requestedLanguageText(key, "Ban do", "Xoa 2525D", "Moi truong", "Thoat", "Canh bao thu cong", "Sinh ly", "Cai dat mang", "Cai dat canh bao", "Cai dat cong cu", "Dieu huong", "Huy", "Bat", "Tat");
        } else if (language.equals("Portuguese")) {
            if (key == :altitude) { return "Altitude"; }
            else if (key == :pressure) { return "Pressao"; }
            else if (key == :temperature) { return "Temperatura"; }
            else if (key == :physiologyView) { return "Fisiologia"; }
            else if (key == :exertion) { return "Esforco"; }
            else if (key == :heartRate) { return "Frequencia cardiaca"; }
            else if (key == :unavailable) { return "Indisponivel"; }
            return requestedLanguageText(key, "Mapa", "Limpar 2525D", "Ambiente", "Sair", "Alerta manual", "Fisiologia", "Preferencias de rede", "Preferencias de alertas", "Preferencias de ferramentas", "Navegacao", "Cancelar", "Ligado", "Desligado");
        } else if (language.equals("Czech")) {
            if (key == :map) { return "Mapa"; }
            else if (key == :clear2525d) { return "Vymazat 2525D"; }
            else if (key == :environment) { return "Prostredi"; }
            else if (key == :exit) { return "Konec"; }
            else if (key == :manualAlert) { return "Rucni upozorneni"; }
            else if (key == :physiology) { return "Fyziologie"; }
            else if (key == :networkPreferences) { return "Predvolby site"; }
            else if (key == :alertingPreferences) { return "Predvolby upozorneni"; }
            else if (key == :toolPreferences) { return "Predvolby nastroju"; }
            else if (key == :locationServices) { return "Polohove sluzby"; }
            else if (key == :userMetrics) { return "Moje udaje"; }
            else if (key == :physiologicalAlerts) { return "Fyziologicka upozorneni"; }
            else if (key == :environmentalAlerts) { return "Prostredni upozorneni"; }
            else if (key == :batteryAlerts) { return "Upozorneni baterie"; }
            else if (key == :immersionAlerts) { return "Upozorneni ponoreni"; }
            else if (key == :atmPressureAlerts) { return "Upozorneni tlaku"; }
            else if (key == :restingHeartRateAlerts) { return "Upozorneni klidove TF"; }
            else if (key == :exertionAlerts) { return "Upozorneni namahy"; }
            else if (key == :chat) { return "Chat"; }
            else if (key == :bloodhoundCompass) { return "Navigace"; }
            else if (key == :clearPointsMain) { return "Vymazat body 2525D"; }
            else if (key == :dropPoint) { return "Vlozit bod 2525D"; }
            else if (key == :clearPointsPrompt) { return "Vymazat body aplikace?"; }
            else if (key == :pointDropped) { return "Bod 2525D vlozen"; }
            else if (key == :locationUnavailable) { return "Poloha nedostupna"; }
            else if (key == :cancel) { return "Zrusit"; }
            else if (key == :selected) { return "Vybrano"; }
            else if (key == :on) { return "Zapnuto"; }
            else if (key == :off) { return "Vypnuto"; }
        } else if (language.equals("Finnish")) {
            if (key == :map) { return "Kartta"; }
            else if (key == :clear2525d) { return "Tyhjenna 2525D"; }
            else if (key == :environment) { return "Ymparisto"; }
            else if (key == :exit) { return "Poistu"; }
            else if (key == :manualAlert) { return "Manuaalinen halytys"; }
            else if (key == :physiology) { return "Fysiologia"; }
            else if (key == :networkPreferences) { return "Verkkoasetukset"; }
            else if (key == :alertingPreferences) { return "Halytysasetukset"; }
            else if (key == :toolPreferences) { return "Tyokaluasetukset"; }
            else if (key == :locationServices) { return "Sijaintipalvelut"; }
            else if (key == :userMetrics) { return "Omat tiedot"; }
            else if (key == :physiologicalAlerts) { return "Fysiologiset halytykset"; }
            else if (key == :environmentalAlerts) { return "Ymparistohalytykset"; }
            else if (key == :batteryAlerts) { return "Akkuhalytykset"; }
            else if (key == :immersionAlerts) { return "Upotushalytykset"; }
            else if (key == :atmPressureAlerts) { return "Ilmanpainehalytykset"; }
            else if (key == :restingHeartRateAlerts) { return "Leposykehalytykset"; }
            else if (key == :exertionAlerts) { return "Rasitushalytykset"; }
            else if (key == :chat) { return "Chat"; }
            else if (key == :bloodhoundCompass) { return "Navigointi"; }
            else if (key == :clearPointsMain) { return "Tyhjenna 2525D-pisteet"; }
            else if (key == :dropPoint) { return "Pudota 2525D-piste"; }
            else if (key == :clearPointsPrompt) { return "Tyhjennetaanko sovelluksen pisteet?"; }
            else if (key == :pointDropped) { return "2525D-piste lisatty"; }
            else if (key == :locationUnavailable) { return "Sijainti ei ole kaytettavissa"; }
            else if (key == :cancel) { return "Peruuta"; }
            else if (key == :selected) { return "Valittu"; }
            else if (key == :on) { return "Paalla"; }
            else if (key == :off) { return "Pois"; }
        } else if (language.equals("Greek")) {
            if (key == :map) { return "Χαρτης"; }
            else if (key == :clear2525d) { return "Καθαρισμος 2525D"; }
            else if (key == :environment) { return "Περιβαλλον"; }
            else if (key == :exit) { return "Εξοδος"; }
            else if (key == :manualAlert) { return "Χειροκινητη ειδοποιηση"; }
            else if (key == :physiology) { return "Φυσιολογια"; }
            else if (key == :networkPreferences) { return "Προτιμησεις δικτυου"; }
            else if (key == :alertingPreferences) { return "Προτιμησεις ειδοποιησεων"; }
            else if (key == :toolPreferences) { return "Προτιμησεις εργαλειων"; }
            else if (key == :locationServices) { return "Υπηρεσιες τοποθεσιας"; }
            else if (key == :userMetrics) { return "Δεδομενα χρηστη"; }
            else if (key == :physiologicalAlerts) { return "Φυσιολογικες ειδοποιησεις"; }
            else if (key == :environmentalAlerts) { return "Περιβαλλοντικες ειδοποιησεις"; }
            else if (key == :batteryAlerts) { return "Ειδοποιησεις μπαταριας"; }
            else if (key == :immersionAlerts) { return "Ειδοποιησεις βυθισης"; }
            else if (key == :atmPressureAlerts) { return "Ειδοποιησεις πιεσης"; }
            else if (key == :restingHeartRateAlerts) { return "Ειδοποιησεις παλμων"; }
            else if (key == :exertionAlerts) { return "Ειδοποιησεις κοπωσης"; }
            else if (key == :chat) { return "Chat"; }
            else if (key == :bloodhoundCompass) { return "Πλοηγηση"; }
            else if (key == :clearPointsMain) { return "Καθαρισμος σημειων 2525D"; }
            else if (key == :dropPoint) { return "Τοποθετηση σημειου 2525D"; }
            else if (key == :clearPointsPrompt) { return "Καθαρισμος σημειων εφαρμογης;"; }
            else if (key == :pointDropped) { return "Το σημειο 2525D τοποθετηθηκε"; }
            else if (key == :locationUnavailable) { return "Η τοποθεσια δεν ειναι διαθεσιμη"; }
            else if (key == :cancel) { return "Ακυρωση"; }
            else if (key == :selected) { return "Επιλεγμενο"; }
            else if (key == :on) { return "Ενεργο"; }
            else if (key == :off) { return "Ανενεργο"; }
        } else if (language.equals("Indonesian")) {
            if (key == :map) { return "Peta"; }
            else if (key == :clear2525d) { return "Hapus 2525D"; }
            else if (key == :environment) { return "Lingkungan"; }
            else if (key == :exit) { return "Keluar"; }
            else if (key == :manualAlert) { return "Peringatan manual"; }
            else if (key == :physiology) { return "Fisiologi"; }
            else if (key == :networkPreferences) { return "Preferensi jaringan"; }
            else if (key == :alertingPreferences) { return "Preferensi peringatan"; }
            else if (key == :toolPreferences) { return "Preferensi alat"; }
            else if (key == :locationServices) { return "Layanan lokasi"; }
            else if (key == :userMetrics) { return "Data pengguna"; }
            else if (key == :physiologicalAlerts) { return "Peringatan fisiologi"; }
            else if (key == :environmentalAlerts) { return "Peringatan lingkungan"; }
            else if (key == :batteryAlerts) { return "Peringatan baterai"; }
            else if (key == :immersionAlerts) { return "Peringatan imersi"; }
            else if (key == :atmPressureAlerts) { return "Peringatan tekanan"; }
            else if (key == :restingHeartRateAlerts) { return "Peringatan detak istirahat"; }
            else if (key == :exertionAlerts) { return "Peringatan upaya"; }
            else if (key == :chat) { return "Chat"; }
            else if (key == :bloodhoundCompass) { return "Navigasi"; }
            else if (key == :clearPointsMain) { return "Hapus titik 2525D"; }
            else if (key == :dropPoint) { return "Letakkan titik 2525D"; }
            else if (key == :clearPointsPrompt) { return "Hapus titik aplikasi?"; }
            else if (key == :pointDropped) { return "Titik 2525D ditambahkan"; }
            else if (key == :locationUnavailable) { return "Lokasi tidak tersedia"; }
            else if (key == :cancel) { return "Batal"; }
            else if (key == :selected) { return "Dipilih"; }
            else if (key == :on) { return "Aktif"; }
            else if (key == :off) { return "Nonaktif"; }
        } else if (language.equals("Latvian")) {
            if (key == :map) { return "Karte"; }
            else if (key == :clear2525d) { return "Notirit 2525D"; }
            else if (key == :environment) { return "Vide"; }
            else if (key == :exit) { return "Iziet"; }
            else if (key == :manualAlert) { return "Manuals bridinajums"; }
            else if (key == :physiology) { return "Fiziologija"; }
            else if (key == :networkPreferences) { return "Tikla preferences"; }
            else if (key == :alertingPreferences) { return "Bridinajumu preferences"; }
            else if (key == :toolPreferences) { return "Riku preferences"; }
            else if (key == :locationServices) { return "Atrasanas vietas pakalpojumi"; }
            else if (key == :userMetrics) { return "Mani dati"; }
            else if (key == :physiologicalAlerts) { return "Fiziologiski bridinajumi"; }
            else if (key == :environmentalAlerts) { return "Vides bridinajumi"; }
            else if (key == :batteryAlerts) { return "Baterijas bridinajumi"; }
            else if (key == :immersionAlerts) { return "Iegremdes bridinajumi"; }
            else if (key == :atmPressureAlerts) { return "Spiediena bridinajumi"; }
            else if (key == :restingHeartRateAlerts) { return "Miera pulsa bridinajumi"; }
            else if (key == :exertionAlerts) { return "Slodzes bridinajumi"; }
            else if (key == :chat) { return "Cata"; }
            else if (key == :bloodhoundCompass) { return "Navigacija"; }
            else if (key == :clearPointsMain) { return "Notirit 2525D punktus"; }
            else if (key == :dropPoint) { return "Novietot 2525D punktu"; }
            else if (key == :clearPointsPrompt) { return "Notirit lietotnes punktus?"; }
            else if (key == :pointDropped) { return "2525D punkts novietots"; }
            else if (key == :locationUnavailable) { return "Atrasanas vieta nav pieejama"; }
            else if (key == :cancel) { return "Atcelt"; }
            else if (key == :selected) { return "Atlasits"; }
            else if (key == :on) { return "Ieslegts"; }
            else if (key == :off) { return "Izslegts"; }
        }
        return "";
    }

    function alertTypeLabel(alertType as String) as String {
        if (alertType.equals("Gate Runner")) { return text(:gateRunner); }
        else if (alertType.equals("Gunshot")) { return text(:gunshot); }
        else if (alertType.equals("Gunshot Injury")) { return text(:gunshotInjury); }
        else if (alertType.equals("Injury")) { return text(:injury); }
        else if (alertType.equals("UAS")) { return text(:uas); }
        else if (alertType.equals("Vehicle")) { return text(:vehicle); }
        return alertType;
    }

    function requestedLanguageText(key as Symbol, mapText as String, clearText as String, environmentText as String, exitText as String, manualText as String, physiologyText as String, networkText as String, alertingText as String, toolsText as String, navigationText as String, cancelText as String, onText as String, offText as String) as String {
        if (key == :map) { return mapText; }
        else if (key == :clear2525d || key == :clearPointsMain) { return clearText; }
        else if (key == :environment) { return environmentText; }
        else if (key == :exit) { return exitText; }
        else if (key == :manualAlert) { return manualText; }
        else if (key == :physiology) { return physiologyText; }
        else if (key == :networkPreferences) { return networkText; }
        else if (key == :alertingPreferences) { return alertingText; }
        else if (key == :toolPreferences) { return toolsText; }
        else if (key == :bloodhoundCompass) { return navigationText; }
        else if (key == :cancel) { return cancelText; }
        else if (key == :on) { return onText; }
        else if (key == :off) { return offText; }
        return "";
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
        } else if (language.equals("Bulgarian")) {
            return "Nastroiki";
        } else if (language.equals("Croatian")) {
            return "Postavke";
        } else if (language.equals("Czech")) {
            return "Nastaveni";
        } else if (language.equals("Danish")) {
            return "Indstillinger";
        } else if (language.equals("Dutch")) {
            return "Instellingen";
        } else if (language.equals("Estonian")) {
            return "Seaded";
        } else if (language.equals("Finnish")) {
            return "Asetukset";
        } else if (language.equals("French")) {
            return "Parametres";
        } else if (language.equals("German")) {
            return "Einstellungen";
        } else if (language.equals("Greek")) {
            return "Ρυθμισεις";
        } else if (language.equals("Hungarian")) {
            return "Beallitasok";
        } else if (language.equals("Hebrew")) {
            return "הגדרות";
        } else if (language.equals("Indonesian")) {
            return "Pengaturan";
        } else if (language.equals("Italian")) {
            return "Impostazioni";
        } else if (language.equals("Japanese")) {
            return "設定";
        } else if (language.equals("Korean")) {
            return "설정";
        } else if (language.equals("Latvian")) {
            return "Iestatijumi";
        } else if (language.equals("Lithuanian")) {
            return "Nustatymai";
        } else if (language.equals("Norwegian")) {
            return "Innstillinger";
        } else if (language.equals("Polish")) {
            return "Ustawienia";
        } else if (language.equals("Portuguese")) {
            return "Configuracoes";
        } else if (language.equals("Romanian")) {
            return "Setari";
        } else if (language.equals("Russian")) {
            return "Настройки";
        } else if (language.equals("Slovak")) {
            return "Nastavenia";
        } else if (language.equals("Slovenian")) {
            return "Nastavitve";
        } else if (language.equals("Spanish")) {
            return "Ajustes";
        } else if (language.equals("Swedish")) {
            return "Installningar";
        } else if (language.equals("Thai")) {
            return "การตั้งค่า";
        } else if (language.equals("Turkish")) {
            return "Ayarlar";
        } else if (language.equals("Ukrainian")) {
            return "Налаштування";
        } else if (language.equals("Vietnamese")) {
            return "Cai dat";
        }
        return "Settings";
    }

    function translatedDevicePreferences() as String {
        if (language.equals("Arabic")) {
            return "تفضيلات الجهاز";
        } else if (language.equals("Bulgarian")) {
            return "Nastroiki na ustroistvo";
        } else if (language.equals("Croatian")) {
            return "Postavke uredaja";
        } else if (language.equals("Czech")) {
            return "Predvolby zarizeni";
        } else if (language.equals("Danish")) {
            return "Enhedsindstillinger";
        } else if (language.equals("Dutch")) {
            return "Apparaatvoorkeuren";
        } else if (language.equals("Estonian")) {
            return "Seadme seaded";
        } else if (language.equals("Finnish")) {
            return "Laiteasetukset";
        } else if (language.equals("French")) {
            return "Preferences appareil";
        } else if (language.equals("German")) {
            return "Gerateeinstellungen";
        } else if (language.equals("Greek")) {
            return "Προτιμησεις συσκευης";
        } else if (language.equals("Hungarian")) {
            return "Eszkozbeallitasok";
        } else if (language.equals("Hebrew")) {
            return "העדפות מכשיר";
        } else if (language.equals("Indonesian")) {
            return "Preferensi perangkat";
        } else if (language.equals("Italian")) {
            return "Preferenze dispositivo";
        } else if (language.equals("Japanese")) {
            return "デバイス設定";
        } else if (language.equals("Korean")) {
            return "장치 설정";
        } else if (language.equals("Latvian")) {
            return "Ierices preferences";
        } else if (language.equals("Lithuanian")) {
            return "Irenginio nustatymai";
        } else if (language.equals("Norwegian")) {
            return "Enhetsvalg";
        } else if (language.equals("Polish")) {
            return "Preferencje urzadzenia";
        } else if (language.equals("Portuguese")) {
            return "Preferencias do dispositivo";
        } else if (language.equals("Romanian")) {
            return "Preferinte dispozitiv";
        } else if (language.equals("Russian")) {
            return "Параметры устройства";
        } else if (language.equals("Slovak")) {
            return "Nastavenia zariadenia";
        } else if (language.equals("Slovenian")) {
            return "Nastavitve naprave";
        } else if (language.equals("Spanish")) {
            return "Preferencias del dispositivo";
        } else if (language.equals("Swedish")) {
            return "Enhetsinstallningar";
        } else if (language.equals("Thai")) {
            return "การตั้งค่าอุปกรณ์";
        } else if (language.equals("Turkish")) {
            return "Cihaz ayarlari";
        } else if (language.equals("Ukrainian")) {
            return "Параметри пристрою";
        } else if (language.equals("Vietnamese")) {
            return "Cai dat thiet bi";
        }
        return "Device Preferences";
    }

    function translatedLanguage() as String {
        if (language.equals("Arabic")) {
            return "اللغة";
        } else if (language.equals("Bulgarian")) {
            return "Ezik";
        } else if (language.equals("Croatian")) {
            return "Jezik";
        } else if (language.equals("Czech")) {
            return "Jazyk";
        } else if (language.equals("Danish")) {
            return "Sprog";
        } else if (language.equals("Dutch")) {
            return "Taal";
        } else if (language.equals("Estonian")) {
            return "Keel";
        } else if (language.equals("Finnish")) {
            return "Kieli";
        } else if (language.equals("French")) {
            return "Langue";
        } else if (language.equals("German")) {
            return "Sprache";
        } else if (language.equals("Greek")) {
            return "Γλωσσα";
        } else if (language.equals("Hungarian")) {
            return "Nyelv";
        } else if (language.equals("Hebrew")) {
            return "שפה";
        } else if (language.equals("Indonesian")) {
            return "Bahasa";
        } else if (language.equals("Italian")) {
            return "Lingua";
        } else if (language.equals("Japanese")) {
            return "言語";
        } else if (language.equals("Korean")) {
            return "언어";
        } else if (language.equals("Latvian")) {
            return "Valoda";
        } else if (language.equals("Lithuanian")) {
            return "Kalba";
        } else if (language.equals("Norwegian")) {
            return "Sprak";
        } else if (language.equals("Polish")) {
            return "Jezyk";
        } else if (language.equals("Portuguese")) {
            return "Idioma";
        } else if (language.equals("Romanian")) {
            return "Limba";
        } else if (language.equals("Russian")) {
            return "Язык";
        } else if (language.equals("Slovak")) {
            return "Jazyk";
        } else if (language.equals("Slovenian")) {
            return "Jezik";
        } else if (language.equals("Spanish")) {
            return "Idioma";
        } else if (language.equals("Swedish")) {
            return "Sprak";
        } else if (language.equals("Thai")) {
            return "ภาษา";
        } else if (language.equals("Turkish")) {
            return "Dil";
        } else if (language.equals("Ukrainian")) {
            return "Мова";
        } else if (language.equals("Vietnamese")) {
            return "Ngon ngu";
        }
        return "Language";
    }

    function languageLabel(selectedLanguage as String) as String {
        if (selectedLanguage.equals("Arabic")) {
            return "العربية (Arabic)";
        } else if (selectedLanguage.equals("Bulgarian")) {
            return "Balgarski (Bulgarian)";
        } else if (selectedLanguage.equals("Croatian")) {
            return "Hrvatski (Croatian)";
        } else if (selectedLanguage.equals("Czech")) {
            return "Cestina (Czech)";
        } else if (selectedLanguage.equals("Danish")) {
            return "Dansk (Danish)";
        } else if (selectedLanguage.equals("Dutch")) {
            return "Nederlands (Dutch)";
        } else if (selectedLanguage.equals("Estonian")) {
            return "Eesti (Estonian)";
        } else if (selectedLanguage.equals("Finnish")) {
            return "Suomi (Finnish)";
        } else if (selectedLanguage.equals("French")) {
            return "Francais (French)";
        } else if (selectedLanguage.equals("German")) {
            return "Deutsch (German)";
        } else if (selectedLanguage.equals("Greek")) {
            return "Ελληνικα (Greek)";
        } else if (selectedLanguage.equals("Hungarian")) {
            return "Magyar (Hungarian)";
        } else if (selectedLanguage.equals("Hebrew")) {
            return "עברית (Hebrew)";
        } else if (selectedLanguage.equals("Indonesian")) {
            return "Bahasa Indonesia (Indonesian)";
        } else if (selectedLanguage.equals("Italian")) {
            return "Italiano (Italian)";
        } else if (selectedLanguage.equals("Japanese")) {
            return "日本語 (Japanese)";
        } else if (selectedLanguage.equals("Korean")) {
            return "한국어 (Korean)";
        } else if (selectedLanguage.equals("Latvian")) {
            return "Latviesu (Latvian)";
        } else if (selectedLanguage.equals("Lithuanian")) {
            return "Lietuviu (Lithuanian)";
        } else if (selectedLanguage.equals("Norwegian")) {
            return "Norsk (Norwegian)";
        } else if (selectedLanguage.equals("Polish")) {
            return "Polski (Polish)";
        } else if (selectedLanguage.equals("Portuguese")) {
            return "Portugues (Portuguese)";
        } else if (selectedLanguage.equals("Romanian")) {
            return "Romana (Romanian)";
        } else if (selectedLanguage.equals("Russian")) {
            return "Русский (Russian)";
        } else if (selectedLanguage.equals("Slovak")) {
            return "Slovencina (Slovak)";
        } else if (selectedLanguage.equals("Slovenian")) {
            return "Slovenscina (Slovenian)";
        } else if (selectedLanguage.equals("Spanish")) {
            return "Espanol (Spanish)";
        } else if (selectedLanguage.equals("Swedish")) {
            return "Svenska (Swedish)";
        } else if (selectedLanguage.equals("Thai")) {
            return "ไทย (Thai)";
        } else if (selectedLanguage.equals("Turkish")) {
            return "Turkce (Turkish)";
        } else if (selectedLanguage.equals("Ukrainian")) {
            return "Українська (Ukrainian)";
        } else if (selectedLanguage.equals("Vietnamese")) {
            return "Tieng Viet (Vietnamese)";
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
        view.setApplication(self);
        return view;
    }

    function getTakClient() as TakClient {
        return takClient;
    }

    function getInitialView() {
        return [buildMainMenu(self), new MainMenuDelegate(self)];
    }
}
