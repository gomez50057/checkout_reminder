import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // ✅ Inicializar timezone correctamente

  final AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Check Out Reminder',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  TextEditingController latController = TextEditingController();
  TextEditingController lonController = TextEditingController();
  TimeOfDay selectedTime = const TimeOfDay(hour: 16, minute: 33);

  @override
  void initState() {
    super.initState();
    loadPreferences();
    startLocationTracking(); // 🔥 Ahora la ubicación se actualiza en tiempo real
  }

  // 🔔 Programar Notificación como Alarma a la Hora Personalizada
  Future<void> scheduleAlarm() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int hour = prefs.getInt('hour') ?? 16;
    int minute = prefs.getInt('minute') ?? 33;

    final now = tz.TZDateTime.now(tz.local);
    final scheduledTime = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'alarm_channel_id',
      'Alarma de salida',
      channelDescription: 'Alarma para recordar marcar salida',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      '🚨 Alarma de salida',
      '¡Marca tu salida ahora!',
      scheduledTime,
      platformChannelSpecifics,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Alarma programada")),
    );
  }

  // 📍 Monitorear Ubicación en Tiempo Real
  void startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // 🔥 Detectar cambios cada 1 metro
      ),
    ).listen((Position position) {
      checkUserLocation(position.latitude, position.longitude);
    });
  }

  // 📍 Verificar si el usuario ha salido del área de trabajo
  Future<void> checkUserLocation(double lat, double lon) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double workLat = prefs.getDouble('latitude') ?? 19.4326;
    double workLon = prefs.getDouble('longitude') ?? -99.1332;

    // 🔍 Medir la distancia entre la ubicación actual y el área de trabajo
    double distance = Geolocator.distanceBetween(lat, lon, workLat, workLon);

    print("Distancia actual: $distance metros");

    // ⚠️ Si la distancia es mayor a 1 metro, mostrar la alerta
    if (distance > 1) {
      showExitAlert();
    }
  }

  // 📢 Mostrar Notificación si el usuario se aleja
  void showExitAlert() {
    flutterLocalNotificationsPlugin.show(
      1,
      "⚠️ Saliste sin marcar salida",
      "🚨 No olvides checar antes de salir.",
      NotificationDetails(
        android: AndroidNotificationDetails(
          'channel_id2',
          'Alerta de salida',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  // 📍 Guardar ubicación actual como "Ubicación de Trabajo"
  Future<void> saveCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('latitude', position.latitude);
    await prefs.setDouble('longitude', position.longitude);

    setState(() {
      latController.text = position.latitude.toString();
      lonController.text = position.longitude.toString();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Ubicación de trabajo guardada")),
    );
  }

  // 📥 Guardar preferencias de hora y coordenadas
  Future<void> savePreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double lat = double.tryParse(latController.text) ?? 19.4326;
    double lon = double.tryParse(lonController.text) ?? -99.1332;

    await prefs.setDouble('latitude', lat);
    await prefs.setDouble('longitude', lon);
    await prefs.setInt('hour', selectedTime.hour);
    await prefs.setInt('minute', selectedTime.minute);

    scheduleAlarm();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Configuración guardada")),
    );
  }

  // 📤 Cargar configuración guardada
  Future<void> loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double lat = prefs.getDouble('latitude') ?? 19.4326;
    double lon = prefs.getDouble('longitude') ?? -99.1332;
    int hour = prefs.getInt('hour') ?? 16;
    int minute = prefs.getInt('minute') ?? 33;

    setState(() {
      latController.text = lat.toString();
      lonController.text = lon.toString();
      selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check Out Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Configuración de Alarma", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextField(controller: latController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Latitud de trabajo")),
            TextField(controller: lonController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Longitud de trabajo")),
            ElevatedButton(onPressed: saveCurrentLocation, child: const Text("📍 Marcar Ubicación Actual")),
            ElevatedButton(onPressed: savePreferences, child: const Text("Guardar Configuración")),
          ],
        ),
      ),
    );
  }
}
