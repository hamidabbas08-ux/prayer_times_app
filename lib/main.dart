String currentFiqh = 'shafi';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:adhan/adhan.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';

@pragma('vm:entry-point')
void playAdhanAlarm() async {
  final player = AudioPlayer();
  try {
    await player.setUrl('https://download.quranicaudio.com/adhan/makkah/abdul_basit.mp3');
    await player.play();
    try {
      final dynamic notificationsPlugin = FlutterLocalNotificationsPlugin();
      
      // 1. انیشلائزیشن کو ڈائنامک کرنا تاکہ ورژن کا پنگا نہ آئے
      dynamic initSettings;
      try {
        dynamic createInit = InitializationSettings.new;
        initSettings = Function.apply(createInit, [], {#android: const AndroidInitializationSettings('@mipmap/ic_launcher')});
      } catch (_) {
        dynamic createInit = InitializationSettings.new;
        initSettings = Function.apply(createInit, [const AndroidInitializationSettings('@mipmap/ic_launcher')]);
      }
      
      await notificationsPlugin.initialize(initSettings);
      
      // 2. چینل ڈیٹیلز کو ڈائنامک بنانا (نیا اور پرانا دونوں ورژن خودکار ہینڈل ہوں گے)
      dynamic androidDetails;
      dynamic createAndroid = AndroidNotificationDetails.new;
      try {
        // اگر نیا ورژن (v17+) ہوا تو یہ چلے گا
        androidDetails = Function.apply(createAndroid, [], {
          #channelId: 'azan_channel',
          #channelName: 'Azan Alarms',
          #importance: Importance.max,
          #priority: Priority.high,
        });
      } catch (_) {
        try {
          // اگر پرانا ورژن ہوا تو یہ چلے گا
          androidDetails = Function.apply(createAndroid, [
            'azan_channel',
            'Azan Alarms',
          ], {
            #importance: Importance.max,
            #priority: Priority.high,
          });
        } catch (e) {
          print("Details creation failed: $e");
        }
      }
      
      if (androidDetails != null) {
        dynamic createNotifDetails = NotificationDetails.new;
        dynamic notifDetails = Function.apply(createNotifDetails, [], {#android: androidDetails});
        
        // 3. نوٹیفیکیشن شو کرنے کا کائناتی پکا طریقہ
        dynamic showFunc = notificationsPlugin.show;
        await Function.apply(showFunc, [
          0,
          'Prayer Time',
          'It is time for prayer. Allaho Akbar.',
          notifDetails
        ]);
      }
    } catch (e) { print("Notification Error: $e"); }
  } catch (e) {
    print("Azan Player Error: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(const PrayerTimesApp());
}

class PrayerTimesApp extends StatelessWidget {
  const PrayerTimesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Prayer Timings',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF007AFF),
        scaffoldBackgroundColor: Colors.white,
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cityName = "لوکیشن حاصل کریں";
  String _countdownText = "--:--:--";
  String _nextPrayerName = "---";
  PrayerTimes? _prayerTimes;
  Timer? _timer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _updateCountdown());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() { _cityName = "اجازت نہیں ملی"; _isLoading = false; });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, position.longitude
      );
      
      String city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? "نامعلوم شہر";

      final coordinates = Coordinates(position.latitude, position.longitude);
      final params = CalculationMethod.muslim_world_league.getParameters();
      params.madhab = Madhab.hanafi;
      final prayerTimes = PrayerTimes.today(coordinates, params);

      setState(() {
        _cityName = city;
        _prayerTimes = prayerTimes;
        _isLoading = false;
      });

      _scheduleNextAzan(prayerTimes);

    } catch (e) {
      setState(() {
        _cityName = "ایرر: لوکیشن آن کریں";
        _isLoading = false;
      });
    }
  }

  void _scheduleNextAzan(PrayerTimes pt) {
    final now = DateTime.now();
    DateTime nextAzanTime = pt.fajr;

    if (now.isBefore(pt.fajr)) nextAzanTime = pt.fajr;
    else if (now.isBefore(pt.dhuhr)) nextAzanTime = pt.dhuhr;
    else if (now.isBefore(pt.asr)) nextAzanTime = pt.asr;
    else if (now.isBefore(pt.maghrib)) nextAzanTime = pt.maghrib;
    else if (now.isBefore(pt.isha)) nextAzanTime = pt.isha;
    else {
      nextAzanTime = pt.fajr.add(const Duration(days: 1));
    }

    AndroidAlarmManager.oneShotAt(
      nextAzanTime,
      1,
      playAdhanAlarm,
      exact: true,
      wakeup: true,
    );
  }

  void _updateCountdown() {
    if (_prayerTimes == null) return;

    final now = DateTime.now();
    DateTime nextTime;
    String name = "";

    if (now.isBefore(_prayerTimes!.fajr)) { nextTime = _prayerTimes!.fajr; name = "Fajr"; }
    else if (now.isBefore(_prayerTimes!.dhuhr)) { nextTime = _prayerTimes!.dhuhr; name = "Dhuhr"; }
    else if (now.isBefore(_prayerTimes!.asr)) { nextTime = _prayerTimes!.asr; name = "Asr"; }
    else if (now.isBefore(_prayerTimes!.maghrib)) { nextTime = _prayerTimes!.maghrib; name = "Maghrib"; }
    else if (now.isBefore(_prayerTimes!.isha)) { nextTime = _prayerTimes!.isha; name = "Isha"; }
    else {
      nextTime = _prayerTimes!.fajr.add(const Duration(days: 1));
      name = "Fajr (کل)";
    }

    final difference = nextTime.difference(now);
    
    if (!mounted) return;
    setState(() {
      _nextPrayerName = name;
      _countdownText = "${difference.inHours.toString().padLeft(2, '0')}:${(difference.inMinutes % 60).toString().padLeft(2, '0')}:${(difference.inSeconds % 60).toString().padLeft(2, '0')}";
    });
  }

  String _formatTime(DateTime time) {
    return DateFormat.jm().format(time);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                _cityName,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Column(
          children: [
            const Column(
          children: [
            const Text("Your Live GPS Location", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 5),
            DropdownButton<String>(
              value: currentFiqh,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 'shafi', child: Text("Fiqh: Standard / Jumhoor")),
                DropdownMenuItem(value: 'hanafi', child: Text("Fiqh: Hanafi")),
              ],
              onChanged: (value) {
                setState(() {
                  currentFiqh = value!;
                  _refreshPrayerTimes();
                });
              },
            ),
          ],
        )
            const SizedBox(height: 5),
            DropdownButton<String>(
              value: currentFiqh,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 'shafi', child: Text("Fiqh: Standard / Jumhoor")),
                DropdownMenuItem(value: 'hanafi', child: Text("Fiqh: Hanafi")),
              ],
              onChanged: (value) {
                setState(() {
                  currentFiqh = value!;
                  _refreshPrayerTimes();
                });
              },
            ),
          ],
        )
              
              const SizedBox(height: 40),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Text("Next Prayer: $_nextPrayerName", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Text(
                      _countdownText,
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFF007AFF), fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              Expanded(
                child: _prayerTimes == null
                    ? const Center(child: Text("Refresh Location"))
                    : ListView(
                        children: [
                          _buildPrayerRow("Fajr", _formatTime(_prayerTimes!.fajr)),
                          _buildPrayerRow("Dhuhr", _formatTime(_prayerTimes!.dhuhr)),
                          _buildPrayerRow("Asr", _formatTime(_prayerTimes!.asr)),
                          _buildPrayerRow("Maghrib", _formatTime(_prayerTimes!.maghrib)),
                          _buildPrayerRow("Isha", _formatTime(_prayerTimes!.isha)),
                        ],
                      ),
              ),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _determinePosition,
                  icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black, fontWeight: FontWeight.bold))
                      : const Icon(Icons.gps_fixed, color: Colors.black, fontWeight: FontWeight.bold),
                  label: Text(_isLoading ? "لوکیشن مل رہی ہے..." : "Refresh Location", style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerRow(String name, String time) {
    bool isCurrent = _nextPrayerName == name;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF262626) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: isCurrent ? Border.all(color: const Color(0xFF007AFF), width: 1) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: TextStyle(fontSize: 18, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: Colors.white, fontWeight: FontWeight.bold)),
          Text(time, style: TextStyle(fontSize: 18, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: Colors.black, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
