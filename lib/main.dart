import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/planner.dart';
import 'src/commute.dart';
import 'src/theme.dart';
import 'src/account.dart';
import 'src/account_widgets.dart';
import 'src/class_calendar.dart';
import 'src/google_journey_map.dart';
import 'src/punctuality_overview.dart';
import 'src/punctuality_notifications.dart';
import 'src/journey_widgets.dart';
import 'src/routing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://lddczxofnfrxiktmsboz.supabase.co',
  );
  const key = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_z-SOgWTq_0WvLyj17b-y9g_PTm1Lto9',
  );
  final storage = RememberMeStorage(
    SharedPreferencesLocalStorage(
      persistSessionKey:
          'sb-${Uri.parse(url).host.split('.').first}-auth-token',
    ),
  );

  await Supabase.initialize(
    url: url,
    publishableKey: key,
    authOptions: FlutterAuthClientOptions(
      localStorage: storage,
      detectSessionInUri: false,
    ),
  );

  final cloud = Supabase.instance.client;
  await GoogleMapsSetup.initialize();
  final account = AccountAuth(cloud, storage: storage);
  await account.initializeLinks();
  unawaited(PunctualityNotifications.initialize());
  runApp(TamarawTimeApp(planner: Planner(cloud), account: account));
}

class TamarawTimeApp extends StatefulWidget {
  const TamarawTimeApp({super.key, this.planner, this.account});
  final Planner? planner;
  final AccountAuth? account;
  @override
  State<TamarawTimeApp> createState() => _AppState();
}

class _AppState extends State<TamarawTimeApp> {
  late final Planner planner = widget.planner ?? Planner(null);
  late final AccountAuth? account =
      widget.account ??
      (planner.cloud == null ? null : AccountAuth(planner.cloud!));
  @override
  void dispose() {
    if (widget.account == null) account?.dispose();
    if (widget.planner == null) planner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: planner,
    builder: (context, _) {
      return MaterialApp(
        title: 'Tamaraw Time',
        debugShowCheckedModeBanner: false,
        theme: tamarawTheme(planner.settings['theme'] as String),
        home: Entry(planner: planner, account: account),
      );
    },
  );
}

class Entry extends StatefulWidget {
  const Entry({super.key, required this.planner, this.account});
  final Planner planner;
  final AccountAuth? account;
  @override
  State<Entry> createState() => _EntryState();
}

class _EntryState extends State<Entry> {
  bool ready = false, busy = false, signup = false, consent = false;
  final email = TextEditingController(), password = TextEditingController();
  String? error;
  String? notice;
  String? activeUserId;
  bool remember = true, leaving = false;
  @override
  void initState() {
    super.initState();
    remember = widget.account?.remember ?? true;
    widget.account?.addListener(accountChanged);
    if (widget.planner.cloud?.auth.currentSession != null &&
        widget.account?.recovering != true &&
        widget.account?.handlingLink != true) {
      unawaited(enter(false));
    }
  }

  void accountChanged() {
    if (!mounted) return;
    final account = widget.account!;
    if (ready &&
        !widget.planner.local &&
        activeUserId != account.client.auth.currentUser?.id) {
      setState(() => ready = false);
      widget.planner.journey.clear();
    }
    if (account.recovering || account.handlingLink) {
      setState(() => ready = false);
    } else if (account.client.auth.currentSession == null &&
        !widget.planner.local) {
      setState(() {
        ready = false;
        busy = false;
      });
      widget.planner.clearMemory();
      unawaited(PunctualityNotifications.cancelAll());
    } else if (account.client.auth.currentSession != null &&
        !ready &&
        !busy &&
        !leaving) {
      unawaited(enter(false));
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.account?.removeListener(accountChanged);
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> enter(bool local) async {
    setState(() => busy = true);
    try {
      await widget.planner.load(deviceOnly: local);
      unawaited(PunctualityNotifications.sync(widget.planner));
      activeUserId = local ? null : widget.planner.cloud?.auth.currentUser?.id;
      if (mounted &&
          widget.account?.recovering != true &&
          widget.account?.handlingLink != true) {
        setState(() => ready = true);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    if (!validEmail(email.text) || validatePassword(password.text) != null) {
      setState(
        () => error = 'Enter an email and a password of at least 6 characters.',
      );
      return;
    }
    if (signup && !consent) {
      setState(() => error = 'Please review and accept the research consent.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final client = widget.planner.cloud!;
      await widget.account?.setRemember(remember);
      if (signup) {
        final result = await client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
        );
        if (result.session == null) {
          setState(
            () => error =
                'Check your email to confirm your account, then sign in.',
          );
          return;
        }
      } else {
        await client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      password.clear();
      await enter(false);
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestExit() async {
    if (leaving) return;
    leaving = true;
    try {
      final local = widget.planner.local;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(
            local ? 'Exit device planner?' : 'Log out of Tamaraw Time?',
          ),
          content: Text(
            local ? 'Your saved classes will stay on this device.' : 'Are you sure you want to log out? You will need to sign in again to access your account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(local ? 'Exit planner' : 'Log out'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.planner.waitForSaves();
      if (!local) await widget.account!.signOut();
      widget.planner.clearMemory();
      if (mounted) {
        setState(() {
          ready = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish logging out. Check your connection and retry; unsaved changes are kept in memory.',
            ),
          ),
        );
      }
    } finally {
      leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (account?.handlingLink == true) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (account?.recovering == true) {
      return Scaffold(
        body: AuthSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Brand(),
              const SizedBox(height: 24),
              Text(
                'Reset your password',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              PasswordUpdateForm(
                account: account!,
                onBusyChanged: (value) => setState(() => busy = value),
                recovery: true,
                onSaved: () async {
                  await account.signOut();
                  if (mounted) {
                    setState(() {
                      ready = false;
                      busy = false;
                      notice =
                          'Password updated. Sign in with your new password.';
                    });
                  }
                },
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await account.signOut();
                        } catch (e) {
                          if (mounted) setState(() => error = accountError(e));
                        }
                      },
                child: const Text('Cancel recovery'),
              ),
              if (error != null) AccountError(error!),
            ],
          ),
        ),
      );
    }
    if (ready) {
      return Dashboard(
        planner: widget.planner,
        account: account,
        onExit: requestExit,
      );
    }
    return Scaffold(
      body: AuthSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Brand(),
            const SizedBox(height: 25),
            Text(
              'Plan smarter. Arrive earlier.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (widget.planner.cloud != null) ...[
              Text(
                signup ? 'Create your account' : 'Welcome back, Tamaraw!',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: email,
                enabled: !busy,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Student email'),
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: password,
                enabled: !busy,
                label: 'Password (at least 6 characters)',
                autofillHints: [
                  signup ? AutofillHints.newPassword : AutofillHints.password,
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: remember,
                onChanged: busy
                    ? null
                    : (value) => setState(() => remember = value!),
                title: const Text('Remember me'),
              ),
              if (!remember)
                const Text(
                  'You will need to sign in again after restarting the app or refreshing the page.',
                ),
              if (!signup)
                TextButton(
                  onPressed: busy || account == null
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ForgotPasswordDialog(
                            account: account,
                            email: email.text,
                          ),
                        ),
                  child: const Text('Forgot password?'),
                ),
              if (signup)
                CheckboxListTile(
                  value: consent,
                  onChanged: (v) => setState(() => consent = v!),
                  title: const Text(
                    'I consent to researchers reviewing class and commute activity. Exact GPS coordinates are never stored in the research database.',
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(signup ? 'Create account' : 'Sign in'),
              ),
              TextButton(
                onPressed: busy ? null : () => setState(() => signup = !signup),
                child: Text(
                  signup
                      ? 'Already registered? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ] else
              const Text(
                'Cloud is not connected yet. You can use a private planner on this device.',
                textAlign: TextAlign.center,
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (account?.callbackError != null)
              AccountError(account!.callbackError!),
            if (notice != null)
              Semantics(liveRegion: true, child: Text(notice!)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : () => enter(true),
              child: const Text('Continue on this device'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Device mode saves your planner locally and does not collect research activity.',
              textAlign: TextAlign.center,
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.planner,
    required this.onExit,
    this.account,
  });
  final Planner planner;
  final AccountAuth? account;
  final Future<void> Function() onExit;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int page = 0;
  bool tutorialOpen = false;
  bool journeySyncPending = false;
  DateTime selectedDate = manilaNow();
  Timer? timer;
  Planner get p => widget.planner;
  @override
  void initState() {
    super.initState();
    p.journey.bindLifecycle();
    p.addListener(plannerChanged);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        if (page == 0) syncJourney();
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncJourney();
      if (p.upcoming.isNotEmpty) unawaited(p.journey.restoreGrantedLocation());
      if (p.payload['onboarding']?['finished'] != true) {
        unawaited(tutorial());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    p.removeListener(plannerChanged);
    p.journey.unbindLifecycle();
    super.dispose();
  }

  void syncJourney() {
    final classes = p.upcoming;
    if (classes.isEmpty) return;
    final next = classes.first;
    final storedMode = p.settings['mode'];
    final mode = const {'Walking', 'Driving'}.contains(storedMode)
        ? storedMode as String
        : 'Transit';
    final arriveBy = nextOccurrence(next, manilaNow()).subtract(
      Duration(hours: 8, minutes: (p.settings['buffer'] as num).toInt()),
    );
    p.journey.configure(
      destination: campusPoints[next['campus']]!,
      label: next['campus'],
      mode: mode,
      arriveBy: arriveBy.isAfter(DateTime.now()) ? arriveBy : null,
    );
  }

  void plannerChanged() {
    if (!mounted || page != 0 || journeySyncPending) return;
    journeySyncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      journeySyncPending = false;
      if (mounted && page == 0) syncJourney();
    });
  }

  void switchPage(int index) {
    p.journey.setActive(index == 0 || index == 2);
    setState(() => page = index);
    if (index == 0) syncJourney();
  }

  Future<void> persist([String? event, bool notify = true]) async {
    try {
      await p.save(event);
      await PunctualityNotifications.sync(p);
      if (mounted && notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              p.local ? 'Saved on this device' : 'Saved to your account',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Save failed. Changes remain in memory; retry saving. $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> tutorial() async {
    if (tutorialOpen || !mounted) return;
    setState(() => page = 0);
    tutorialOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const OnboardingTutorial(),
    );
    tutorialOpen = false;
    if (!mounted || p.payload['onboarding']?['finished'] == true) return;
    p.payload['onboarding'] = {'finished': true};
    await persist(null, false);
  }

  Future<void> addClass([Map<String, dynamic>? existing]) async {
    final name = TextEditingController(text: existing?['name']),
        room = TextEditingController(text: existing?['room']);
    int day = existing?['day'] ?? selectedDate.weekday % 7;
    final weekdays = existing == null
        ? <int>{day}
        : classWeekdays(existing).toSet();
    String campus = existing?['campus'] ?? p.settings['campus'];
    TimeOfDay parse(String s) {
      final v = s.split(':').map(int.parse).toList();
      return TimeOfDay(hour: v[0], minute: v[1]);
    }

    var start = parse(existing?['time'] ?? '09:00'),
        end = parse(existing?['end'] ?? '10:30');
    String? validation;
    final classDialog = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(existing == null ? 'Add class' : 'Edit class'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Subject name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Repeats weekly on'),
                  ),
                  Wrap(
                    spacing: 6,
                    children: List.generate(
                      7,
                      (i) => FilterChip(
                        label: Text(days[i].substring(0, 3)),
                        selected: weekdays.contains(i),
                        onSelected: (selected) => update(() {
                          selected ? weekdays.add(i) : weekdays.remove(i);
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: room,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Room'),
                  ),
                  ListTile(
                    title: const Text('Starts'),
                    trailing: Text(classTime('${start.hour}:${start.minute}')),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: start,
                        builder: (ctx, child) => MediaQuery(
                          data: MediaQuery.of(ctx)
                              .copyWith(alwaysUse24HourFormat: false),
                          child: child!,
                        ),
                      );
                      if (t != null) update(() => start = t);
                    },
                  ),
                  ListTile(
                    title: const Text('Ends'),
                    trailing: Text(classTime('${end.hour}:${end.minute}')),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: end,
                        builder: (ctx, child) => MediaQuery(
                          data: MediaQuery.of(ctx)
                              .copyWith(alwaysUse24HourFormat: false),
                          child: child!,
                        ),
                      );
                      if (t != null) update(() => end = t);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: campus,
                    isExpanded: true,
                    items: campuses
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => campus = v!,
                    decoration: const InputDecoration(labelText: 'Campus'),
                  ),
                  if (validation != null) Text(validation!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    weekdays.isEmpty ||
                    end.hour * 60 + end.minute <=
                        start.hour * 60 + start.minute) {
                  update(
                    () => validation = 'Enter a subject, select a weekday and choose an end time after the start.',
                  );
                  return;
                }
                String time(TimeOfDay t) =>
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                final candidate = {
                  ...?existing,
                  'id':
                      existing?['id'] ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  'name': name.text.trim(),
                  'room': room.text.trim(),
                  'day': weekdays.contains(day)
                      ? day
                      : (weekdays.toList()..sort()).first,
                  'weekdays': weekdays.toList()..sort(),
                  'time': time(start),
                  'end': time(end),
                  'campus': campus,
                };
                final conflict = p.classes
                    .where((c) => c['id'] != candidate['id'])
                    .firstWhere(
                      (c) => classesOverlap(candidate, c),
                      orElse: () => <String, dynamic>{},
                    );
                if (conflict.isNotEmpty) {
                  final sharedDay = classWeekdays(candidate)
                      .toSet()
                      .intersection(classWeekdays(conflict).toSet())
                      .first;
                  update(
                    () => validation =
                        '${conflict['name']} overlaps this class at ${conflict['time']}–${conflict['end']} on ${days[sharedDay]}.',
                  );
                  return;
                }
                Navigator.pop(ctx, candidate);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(classDialog);
    if (result != null) {
      final list = p.classes;
      list.removeWhere((c) => c['id'] == result['id']);
      list.add(result);
      p.payload['classes'] = list;
      await persist(existing == null ? 'class_added' : null);
    }
    await classDialog.completed;
    name.dispose();
    room.dispose();
  }

  Widget classTile(Map<String, dynamic> c) => Card(
    child: ListTile(
      isThreeLine: true,
      leading: const Icon(Icons.school_outlined),
      title: Text(c['name']),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${classWeekdays(c).map((d) => days[d].substring(0, 3)).join(', ')} · ${classTime(c['time'])}–${classTime(c['end'])}\n${c['campus']} · ${c['room'].toString().isEmpty ? 'Room not set' : c['room']}',
          ),
          Text(classStatus(c, manilaNow())),
        ],
      ),
      onTap: () => addClass(c),
      trailing: IconButton(
        tooltip: 'Delete class',
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete ${c['name']}?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (yes == true) {
            p.payload['classes'] = p.classes
              ..removeWhere((a) => a['id'] == c['id']);
            await persist('class_deleted');
          }
        },
      ),
    ),
  );
  Widget home() {
    final upcoming = p.upcoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PunctualityOverview(planner: p, onCommute: () => switchPage(2)),
        const SizedBox(height: 24),
        SectionHeading(
          'Upcoming classes',
          trailing: TextButton.icon(
            onPressed: () => switchPage(1),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('View schedule'),
          ),
        ),
        const SizedBox(height: 16),
        if (upcoming.isEmpty)
          const MobilityCard(
            child: Text(
              'Your class list is empty. Tap + to add your first class.',
            ),
          ),
        ...upcoming.take(4).map(classTile),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: p,
    builder: (context, _) => PlannerShell(
      page: page,
      local: p.local,
      onPage: switchPage,
      onExit: widget.onExit,
      floatingActionButton: page < 2
          ? FloatingActionButton(
              onPressed: () => addClass(),
              tooltip: 'Add class',
              child: const Icon(Icons.add),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: TamarawPalette.of(context).soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const LivePlannerClock(),
              ),
              Text(
                p.local
                    ? 'DEVICE PLANNER · Saved locally'
                    : 'CLOUD PLANNER · ${p.cloud?.auth.currentUser?.email}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 24),
          PageEntrance(
            key: ValueKey(page),
            child: switch (page) {
              0 => home(),
              1 => ClassCalendar(
                classes: p.classes,
                selected: selectedDate,
                onSelected: (date) => setState(() => selectedDate = date),
                classTile: classTile,
                onAdd: () => addClass(),
              ),
              2 => Card(
                child: Padding(
                  padding: const EdgeInsets.all(23),
                  child: Commute(
                    planner: p,
                    onSave: () => persist('commute_saved'),
                  ),
                ),
              ),
              _ => Card(
                child: Padding(
                  padding: const EdgeInsets.all(23),
                  child: Preferences(
                    planner: p,
                    account: widget.account,
                    onSave: () => persist('settings_saved'),
                    onTutorial: tutorial,
                  ),
                ),
              ),
            },
          ),
          const SizedBox(height: 34),
          Text(
            '© Tamaraw Time · Student companion · Plan smarter. Arrive earlier.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class OnboardingTutorial extends StatefulWidget {
  const OnboardingTutorial({super.key});

  @override
  State<OnboardingTutorial> createState() => _OnboardingTutorialState();
}

class _OnboardingTutorialState extends State<OnboardingTutorial> {
  static const steps = <({String label, String title, String tip})>[
    (
      label: '01 · DASHBOARD',
      title: 'Your day, already planned',
      tip: 'Upcoming class and departure time appear automatically.',
    ),
    (
      label: '02 · CLASS SCHEDULE',
      title: 'Choose your class time',
      tip: 'Use the visible AM/PM buttons when adding your subject.',
    ),
    (
      label: '03 · AUTOMATIC TIMING',
      title: 'Find your best departure',
      tip: 'Arrival buffer, travel estimate, and get-ready time shape your routine.',
    ),
    (
      label: '04 · GPS TRACKING',
      title: 'See your commute live',
      tip: 'With location permission, a live position can improve walking and driving estimates.',
    ),
    (
      label: '05 · PERSONALIZE',
      title: 'Make Tamaraw Time yours',
      tip: 'Change your color theme any time under Settings.',
    ),
  ];

  int index = 0;

  void close() => Navigator.of(context).pop();

  Widget scene(BuildContext context) {
    final palette = TamarawPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final surface = colors.surface;
    final border = palette.border;
    Widget tile(
      String label,
      String value,
      String note, {
      bool highlight = false,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: highlight ? palette.green : palette.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );

    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: palette.green),
                const SizedBox(width: 8),
                const Expanded(child: Text('Good morning, Tamaraw!')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tile('NEXT CLASS', 'Data Structures', '9:00 AM'),
                const SizedBox(width: 8),
                tile(
                  'LEAVE BY',
                  '7:50 AM',
                  'Calculated for you',
                  highlight: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(value: .72, minHeight: 7),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_outlined, color: palette.green),
                const SizedBox(width: 8),
                const Text('New class'),
              ],
            ),
            const SizedBox(height: 12),
            _tutorialField(context, 'Data Structures'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '9 : 00',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                _timeChip(context, 'AM', selected: true),
                const SizedBox(width: 6),
                _timeChip(context, 'PM'),
              ],
            ),
            const SizedBox(height: 8),
            _tutorialField(context, 'Monday · FEU Tech'),
          ],
        );
      case 2:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _equationPart(context, 'Class', '9:00 AM'),
                const Icon(Icons.remove, size: 18),
                _equationPart(context, 'Travel', '55 min'),
                const Icon(Icons.remove, size: 18),
                _equationPart(context, 'Buffer', '15 min'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.forest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('LEAVE BY', style: TextStyle(color: palette.yellow)),
                  Text(
                    '7:50 AM',
                    style: TextStyle(
                      color: palette.yellow,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('GET READY  ·  7:05 AM', textAlign: TextAlign.center),
          ],
        );
      case 3:
        return SizedBox(
          height: 210,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: palette.paper)),
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('tutorial-route-map'),
                    painter: _TutorialMapPainter(
                      palette: palette,
                      routeColor: colors.primary,
                    ),
                  ),
                ),
                Positioned(
                  left: 22,
                  bottom: 50,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xff27824b),
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.my_location, size: 18),
                  ),
                ),
                Positioned(
                  right: 18,
                  top: 8,
                  child: const Icon(
                    Icons.location_on,
                    size: 38,
                    color: Color(0xffd44940),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: _mapTag(context, 'YOU', const Color(0xff27824b)),
                ),
                Positioned(
                  right: 10,
                  bottom: 8,
                  child: _mapTag(context, 'CAMPUS', const Color(0xffd44940)),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: palette.border),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text('ROUTE PREVIEW'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        final themes = TamarawPalette.themes.values.toList();
        return Column(
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: palette.green),
                const SizedBox(width: 8),
                const Text('Choose your colors'),
              ],
            ),
            const SizedBox(height: 12),
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var column = 0; column < 2; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(child: _themeSample(themes[row * 2 + column])),
                  ],
                ],
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = steps[index];
    final colors = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * .9;
    return Dialog(
      key: const ValueKey('tutorial-dialog'),
      insetPadding: const EdgeInsets.all(14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 630, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'GETTING STARTED',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tutorial',
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 210),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: TamarawPalette.of(context).soft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TamarawPalette.of(context).border),
                ),
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.noScaling),
                    child: scene(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                step.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                step.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(step.tip),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(
                        steps.length,
                        (dot) => Container(
                          width: dot == index ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: dot == index
                                ? colors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text('${index + 1} / ${steps.length}'),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: close,
                    child: const Text('Skip for now'),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: index == 0
                            ? null
                            : () => setState(() => index--),
                        child: const Text('Back'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: index == steps.length - 1
                            ? close
                            : () => setState(() => index++),
                        child: Text(
                          index == steps.length - 1
                              ? 'Start using the app'
                              : 'Next',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tutorialField(BuildContext context, String label) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: TamarawPalette.of(context).border),
    ),
    child: Text(label),
  );

  Widget _timeChip(
    BuildContext context,
    String label, {
    bool selected = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _equationPart(BuildContext context, String label, String value) =>
      Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      );

  Widget _mapTag(BuildContext context, String label, Color markerColor) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: TamarawPalette.of(context).border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: markerColor),
              const SizedBox(width: 5),
              Text(label),
            ],
          ),
        ),
      );

  Widget _themeSample(TamarawPalette theme) => Container(
    key: ValueKey('tutorial-theme-${theme.name}'),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: theme.paper,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: theme.border),
    ),
    child: Row(
      children: [
        Container(
          key: ValueKey('tutorial-theme-swatch-${theme.name}'),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.heroStart, theme.heroFinish],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: theme.yellow,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            theme.name,
            style: TextStyle(
              color: theme.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TutorialMapPainter extends CustomPainter {
  const _TutorialMapPainter({required this.palette, required this.routeColor});

  final TamarawPalette palette;
  final Color routeColor;

  @override
  void paint(Canvas canvas, Size size) {
    Offset point(double x, double y) => Offset(size.width * x, size.height * y);
    final blocks = [
      (0.25, 0.08, 0.43, 0.17),
      (0.56, 0.08, 0.74, 0.17),
      (0.05, 0.28, 0.14, 0.42),
      (0.25, 0.28, 0.43, 0.42),
      (0.56, 0.28, 0.74, 0.42),
      (0.86, 0.28, 0.96, 0.42),
      (0.05, 0.54, 0.14, 0.69),
      (0.25, 0.54, 0.43, 0.69),
      (0.56, 0.54, 0.74, 0.69),
      (0.86, 0.54, 0.96, 0.69),
      (0.25, 0.82, 0.43, 0.94),
      (0.56, 0.82, 0.74, 0.94),
    ];
    final blockPaint = Paint()..color = palette.highlight;
    for (final (left, top, right, bottom) in blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(point(left, top), point(right, bottom)),
          const Radius.circular(5),
        ),
        blockPaint,
      );
    }

    final streets = <Path>[
      Path()
        ..moveTo(-8, size.height * .22)
        ..lineTo(size.width + 8, size.height * .22),
      Path()
        ..moveTo(-8, size.height * .48)
        ..lineTo(size.width + 8, size.height * .48),
      Path()
        ..moveTo(-8, size.height * .76)
        ..lineTo(size.width + 8, size.height * .76),
      Path()
        ..moveTo(size.width * .2, -8)
        ..lineTo(size.width * .2, size.height + 8),
      Path()
        ..moveTo(size.width * .5, -8)
        ..lineTo(size.width * .5, size.height + 8),
      Path()
        ..moveTo(size.width * .8, -8)
        ..lineTo(size.width * .8, size.height + 8),
    ];
    final streetEdge = Paint()
      ..color = palette.border
      ..strokeWidth = 23
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final streetFill = Paint()
      ..color = palette.surface
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final street in streets) {
      canvas.drawPath(street, streetEdge);
      canvas.drawPath(street, streetFill);
    }

    final route = Path()
      ..moveTo(size.width * .2, size.height * .76)
      ..lineTo(size.width * .5, size.height * .76)
      ..lineTo(size.width * .5, size.height * .48)
      ..lineTo(size.width * .8, size.height * .48)
      ..lineTo(size.width * .8, size.height * .22)
      ..lineTo(size.width * .94, size.height * .22);
    final routeCasing = Paint()
      ..color = palette.surface
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final routePaint = Paint()
      ..color = routeColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(route, routeCasing);
    canvas.drawPath(route, routePaint);
  }

  @override
  bool shouldRepaint(covariant _TutorialMapPainter oldDelegate) =>
      palette != oldDelegate.palette || routeColor != oldDelegate.routeColor;
}

class Preferences extends StatefulWidget {
  const Preferences({
    super.key,
    required this.planner,
    required this.onSave,
    required this.onTutorial,
    this.account,
  });
  final Planner planner;
  final AccountAuth? account;
  final Future<void> Function() onSave, onTutorial;
  @override
  State<Preferences> createState() => _PreferencesState();
}

class _PreferencesState extends State<Preferences> {
  var form = GlobalKey<FormState>();
  late final draft = Map<String, dynamic>.from(widget.planner.settings);
  late bool customTrafficBuffer = !const [
    15,
    30,
    45,
    60,
  ].contains((draft['trafficBufferMinutes'] as num?)?.toInt() ?? 30);
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Student preferences',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        const Brand(),
        const SizedBox(height: 20),
        Text('Account Security', style: Theme.of(context).textTheme.titleLarge),
        if (widget.planner.local || widget.account == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Sign in to a cloud account to change your password.'),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showChangePassword(context, widget.account!),
          ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: draft['name'],
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (v) => v!.trim().isEmpty ? 'Enter your name' : null,
          onSaved: (v) => draft['name'] = v!.trim(),
        ),
        const SizedBox(height: 12),
        for (final entry in {'campus': campuses, 'mode': modes}.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              initialValue: draft[entry.key],
              isExpanded: true,
              decoration: InputDecoration(
                labelText: {
                  'campus': 'Preferred campus',
                  'mode': 'Travel mode',
                  'theme': 'Color scheme',
                }[entry.key],
              ),
              items: entry.value
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                        {
                              'forest': 'FEU Forest',
                              'ocean': 'Coastal Blue',
                              'sunset': 'Golden Hour',
                              'night': 'Midnight',
                            }[v] ??
                            v,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => draft[entry.key] = v,
            ),
          ),
        Text('Color scheme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 9),
        ThemeChoices(
          value: draft['theme'] as String,
          onChanged: (value) async {
            setState(() => draft['theme'] = value);
            widget.planner.settings['theme'] = value;
            await widget.planner.save();
          },
        ),
        const SizedBox(height: 20),
        for (final key in ['travel', 'prep', 'buffer'])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
              initialValue: '${draft[key]}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: {
                  'travel': 'Manual journey minutes',
                  'prep': 'Preparation minutes',
                  'buffer': 'Arrival buffer minutes',
                }[key],
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                final max = key == 'travel' ? 2880 : 480;
                return n == null || n < (key == 'travel' ? 1 : 0) || n > max
                    ? 'Enter ${key == 'travel' ? 1 : 0}–$max minutes'
                    : null;
              },
              onSaved: (v) => draft[key] = int.parse(v!),
            ),
          ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: customTrafficBuffer
              ? 'custom'
              : '${(draft['trafficBufferMinutes'] as num?)?.toInt() ?? 30}',
          decoration: const InputDecoration(
            labelText: 'Driving traffic allowance',
            helperText: 'Added to the road estimate; not live traffic.',
          ),
          items: const [15, 30, 45, 60]
              .map(
                (minutes) => DropdownMenuItem(
                  value: '$minutes',
                  child: Text('$minutes minutes'),
                ),
              )
              .followedBy(const [
                DropdownMenuItem(value: 'custom', child: Text('Custom')),
              ])
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              customTrafficBuffer = value == 'custom';
              if (!customTrafficBuffer) {
                draft['trafficBufferMinutes'] = int.parse(value);
              }
            });
          },
        ),
        if (customTrafficBuffer)
          TextFormField(
            initialValue: '${draft['trafficBufferMinutes']}',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom traffic allowance (minutes)',
            ),
            validator: (value) {
              final minutes = int.tryParse(value ?? '');
              return minutes == null || minutes < 0 || minutes > 480
                  ? 'Enter 0–480 minutes'
                  : null;
            },
            onSaved: (value) =>
                draft['trafficBufferMinutes'] = int.parse(value!),
          ),
        if (customTrafficBuffer) const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: draft['punctualityNotificationsEnabled'] == true,
          title: const Text('Punctuality notifications'),
          subtitle: Text(
            PunctualityNotifications.isSupported
                ? 'Preparation, leave-by, and class-start reminders while the app is closed.'
                : 'Notifications are available on Android and iOS.',
          ),
          onChanged: PunctualityNotifications.isSupported
              ? (value) async {
                  setState(
                    () => draft['punctualityNotificationsEnabled'] = value,
                  );
                  widget.planner.settings['punctualityNotificationsEnabled'] =
                      value;
                  final permissionGranted = value
                      ? await PunctualityNotifications.requestPermission()
                      : true;
                  await widget.onSave();
                  if (value && !permissionGranted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Reminders are saved, but Android may hide them until notifications are allowed.',
                        ),
                        action: SnackBarAction(
                          label: 'Settings',
                          onPressed: () => unawaited(
                            PunctualityNotifications.openSystemSettings(),
                          ),
                        ),
                      ),
                    );
                  }
                }
              : null,
        ),
        if (PunctualityNotifications.isSupported &&
            draft['punctualityNotificationsEnabled'] == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final failure =
                        await PunctualityNotifications.showTestNotification();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          failure ?? 'Test alert sent. Check the notification and preparation sound.',
                        ),
                        action: failure == null
                            ? null
                            : SnackBarAction(
                                label: 'Settings',
                                onPressed: () => unawaited(
                                  PunctualityNotifications.openSystemSettings(),
                                ),
                              ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send test notification'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final failure =
                        await PunctualityNotifications.scheduleTestNotificationInTenSeconds();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          failure ?? 'Test alert scheduled for 10 seconds from now. Close the app; Android may delay it if exact alarms are off.',
                        ),
                        action: failure == null
                            ? null
                            : SnackBarAction(
                                label: 'Settings',
                                onPressed: () => unawaited(
                                  PunctualityNotifications.openSystemSettings(),
                                ),
                              ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.schedule_send_outlined),
                  label: const Text('Send test notification in 10 seconds'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await PunctualityNotifications.sync(widget.planner);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(PunctualityNotifications.lastSyncStatus),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Refresh class reminders'),
                ),
              ],
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: draft['useManualEstimate'] == true,
          title: const Text('Use a manual fallback'),
          subtitle: const Text(
            'Show your manual plan when a fresh route estimate is unavailable.',
          ),
          onChanged: (value) =>
              setState(() => draft['useManualEstimate'] = value),
        ),
        FilledButton(
          onPressed: () async {
            if (form.currentState!.validate()) {
              form.currentState!.save();
              widget.planner.payload['settings'] = Map<String, dynamic>.from(
                draft,
              );
              await widget.onSave();
            }
          },
          child: const Text('Save settings'),
        ),
        TextButton.icon(
          onPressed: widget.onTutorial,
          icon: const Icon(Icons.help_outline),
          label: const Text('Replay tutorial guide'),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert({
                  'classes': widget.planner.classes,
                  'settings': widget.planner.settings,
                  'exportedAt': DateTime.now().toUtc().toIso8601String(),
                }),
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Schedule JSON copied. Paste into a file to keep a backup.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy schedule backup (JSON)'),
        ),
        if (!widget.planner.local)
          TextButton.icon(
            onPressed: () async {
              try {
                await widget.planner.waitForSaves();
                await widget.planner.load();
                unawaited(PunctualityNotifications.sync(widget.planner));
                if (mounted) {
                  setState(() {
                    draft.clear();
                    draft.addAll(widget.planner.settings);
                    form = GlobalKey<FormState>();
                  });
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
                }
              }
            },
            icon: const Icon(Icons.sync),
            label: const Text('Refresh cloud data'),
          ),
        TextButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear schedule and preferences?'),
                content: const Text(
                  'This removes your saved classes and restores default settings.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Clear planner'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              widget.planner.payload = Planner.fresh()
                ..['onboarding'] = {'finished': true};
              await widget.onSave();
              if (mounted) {
                setState(() {
                  draft.clear();
                  draft.addAll(widget.planner.settings);
                  form = GlobalKey<FormState>();
                });
              }
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear schedule and preferences'),
        ),
        const SizedBox(height: 16),
        const Text(
          'GPS runs on Home or Commute in the foreground after permission, and stops when disabled or the app is backgrounded. Coordinates are shared with routing providers to plan a journey, never saved as location history or research data. Traffic and timetable coverage depend on the provider.',
        ),
      ],
    ),
  );
}
