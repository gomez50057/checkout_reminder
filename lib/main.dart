import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  tz.initializeTimeZones();

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
  // Controladores para las coordenadas y el umbral de distancia
  TextEditingController latController = TextEditingController();
  TextEditingController lonController = TextEditingController();
  TextEditingController distanceController = TextEditingController();
  // Hora de la alarma
  TimeOfDay selectedTime = const TimeOfDay(hour: 16, minute: 33);

  @override
  void initState() {
    super.initState();
    loadPreferences();
    startLocationTracking();
  }

  // Cargar configuración guardada: coordenadas, hora y umbral
  Future<void> loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double lat = prefs.getDouble('latitude') ?? 19.4326;
    double lon = prefs.getDouble('longitude') ?? -99.1332;
    int hour = prefs.getInt('hour') ?? 16;
    int minute = prefs.getInt('minute') ?? 33;
    double threshold = prefs.getDouble('threshold') ?? 1.0;

    setState(() {
      latController.text = lat.toString();
      lonController.text = lon.toString();
      distanceController.text = threshold.toString();
      selectedTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  // Guardar configuración (coordenadas, hora, umbral) y programar la alarma
  Future<void> savePreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double lat = double.tryParse(latController.text) ?? 19.4326;
    double lon = double.tryParse(lonController.text) ?? -99.1332;
    double threshold = double.tryParse(distanceController.text) ?? 1.0;

    await prefs.setDouble('latitude', lat);
    await prefs.setDouble('longitude', lon);
    await prefs.setInt('hour', selectedTime.hour);
    await prefs.setInt('minute', selectedTime.minute);
    await prefs.setDouble('threshold', threshold);

    scheduleAlarm();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Configuración guardada")),
    );
  }

  // Función para capturar la ubicación actual y actualizar los campos
  Future<void> captureCurrentLocation() async {
    try {
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
        const SnackBar(content: Text("Ubicación actual capturada")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al capturar la ubicación: $e")),
      );
    }
  }

  // Programar la notificación (alarma) según la hora configurada
  Future<void> scheduleAlarm() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int hour = prefs.getInt('hour') ?? 16;
    int minute = prefs.getInt('minute') ?? 33;

    final now = tz.TZDateTime.now(tz.local);
    final scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

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
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Iniciar el monitoreo de ubicación en tiempo real (cada 1 metro)
  void startLocationTracking() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      checkUserLocation(position.latitude, position.longitude);
    });
  }

  // Verificar si el usuario se alejó del área de trabajo según el umbral configurado
  Future<void> checkUserLocation(double lat, double lon) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double workLat = prefs.getDouble('latitude') ?? 19.4326;
    double workLon = prefs.getDouble('longitude') ?? -99.1332;
    double threshold = prefs.getDouble('threshold') ?? 1.0;

    double distance = Geolocator.distanceBetween(lat, lon, workLat, workLon);
    debugPrint("Distancia actual: $distance metros");

    if (distance > threshold) {
      showExitAlert();
    }
  }

  // Mostrar notificación de alerta si se excede el umbral
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

  // Selector de hora para configurar la hora de la alarma
  Future<void> selectTime(BuildContext context) async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: selectedTime);
    if (picked != null) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check Out Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Configuración de Alarma",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(
                controller: latController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "Latitud de trabajo"),
              ),
              TextField(
                controller: lonController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "Longitud de trabajo"),
              ),
              TextField(
                controller: distanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: "Distancia umbral (metros)"),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: captureCurrentLocation,
                child: const Text("📍 Tomar Ubicación Actual"),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text("Hora de alarma: ${selectedTime.format(context)}"),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => selectTime(context),
                    child: const Text("Cambiar Hora"),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: savePreferences,
                child: const Text("Guardar Configuración"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Inicializar el servicio en segundo plano usando flutter_background_service y flutter_background_service_android
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  // Cada 15 segundos en segundo plano, verificar la ubicación
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    double lat = position.latitude;
    double lon = position.longitude;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    double workLat = prefs.getDouble('latitude') ?? 19.4326;
    double workLon = prefs.getDouble('longitude') ?? -99.1332;
    double threshold = prefs.getDouble('threshold') ?? 1.0;

    double distance = Geolocator.distanceBetween(lat, lon, workLat, workLon);

    if (distance > threshold) {
      flutterLocalNotificationsPlugin.show(
        2,
        "⚠️ Saliste sin marcar salida",
        "🚨 No olvides checar antes de salir.",
        const NotificationDetails(
          android: AndroidNotificationDetails('channel_id3', 'Alerta de salida'),
        ),
      );
    }
  });
}
