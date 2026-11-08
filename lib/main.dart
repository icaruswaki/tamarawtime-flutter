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
import 'src/responsive.dart';

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
  final account = AccountAuth(cloud, storage: storage);
  await account.initializeLinks();
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
  int? tutorialIndex;
  DateTime selectedDate = manilaNow();
  Timer? timer;
  Planner get p => widget.planner;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (p.payload['onboarding']?['finished'] != true) {
        setState(() => tutorialIndex = 0);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> persist([String? event, bool notify = true]) async {
    try {
      await p.save(event);
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
    setState(() {
      page = 0;
      tutorialIndex = 0;
    });
  }

  Future<void> finishTutorial() async {
    setState(() => tutorialIndex = null);
    p.payload['onboarding'] = {'finished': true};
    await persist(null, false);
  }

  void skipTutorialStep() {
    switch (tutorialIndex) {
      case 0:
        setState(() {
          page = 1;
          tutorialIndex = 1;
        });
        return;
      case 1:
        setState(() {
          page = 2;
          tutorialIndex = 2;
        });
        return;
      case 2:
        setState(() {
          page = 3;
          tutorialIndex = 3;
        });
        return;
      case 3:
        finishTutorial();
        return;
      default:
        return;
    }
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
                Navigator.pop(ctx, {
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
                });
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
      if (mounted && tutorialIndex == 1) {
        setState(() {
          tutorialIndex = 2;
          page = 2;
        });
      }
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
      subtitle: Text(
        '${classWeekdays(c).map((d) => days[d].substring(0, 3)).join(', ')} · ${classTime(c['time'])}–${classTime(c['end'])}\n${c['campus']} · ${c['room'].toString().isEmpty ? 'Room not set' : c['room']}',
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
    final colors = TamarawPalette.of(context);
    final upcoming = p.upcoming;
    final next = upcoming.isEmpty ? null : upcoming.first;
    final travel = (p.settings['travel'] as num).toInt();
    final when = next == null ? null : nextOccurrence(next, manilaNow());
    final leave = when?.subtract(
      Duration(minutes: travel + (p.settings['buffer'] as num).toInt()),
    );
    final ready = leave?.subtract(
      Duration(minutes: (p.settings['prep'] as num).toInt()),
    );
    final tiles = [
      StatTile(
        label: 'NEXT CLASS',
        value: next?['name'] ?? 'No classes yet',
        note: next == null
            ? 'Add your first class to begin'
            : '${days[next['day']]} · ${next['time']}',
        accent: true,
      ),
      StatTile(
        label: 'SUGGESTED LEAVE TIME',
        value: leave == null ? '—' : clock(leave),
        note: 'Class start, journey and arrival buffer',
      ),
      StatTile(
        label: 'TRAVEL ESTIMATE',
        value: '$travel min',
        note: 'Default estimate · ${p.settings['mode']}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YOUR PERSONAL CAMPUS COMPANION',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 7),
        Text(
          'Good day, ${p.settings['name']}!',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        Text(
          'Focus on arriving to class on time.',
          style: TextStyle(color: colors.muted),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) =>
              AppLayout.columns(
                box.maxWidth,
                textScale: AppLayout.textScale(context),
              )
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 19),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final tile in tiles)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: tile,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        Text(
          'Plan for punctuality',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [colors.heroStart, colors.heroFinish],
            ),
          ),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: Colors.white, fontSize: 14, height: 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  next == null
                      ? 'YOUR PUNCTUALITY ASSISTANT'
                      : 'UPCOMING CLASS · ${days[next['day']].toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Color(0xffc4decd),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  leave == null
                      ? 'Add your schedule to start'
                      : 'Leave by ${clock(leave)}',
                  style: const TextStyle(
                    fontSize: 29,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  ready == null
                      ? 'Get a personalized departure recommendation'
                      : 'Prepare by ${clock(ready)} · Aim to arrive ${clock(when!.subtract(Duration(minutes: (p.settings['buffer'] as num).toInt())))}',
                  style: const TextStyle(color: Color(0xffc4decd)),
                ),
                if (leave != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      leave.difference(manilaNow()).inMinutes < 0
                          ? 'Recommended departure has passed'
                          : 'Leave in ${leave.difference(manilaNow()).inHours} hr ${leave.difference(manilaNow()).inMinutes % 60} min',
                      style: TextStyle(
                        color: colors.yellow,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => setState(() => page = 2),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.yellow,
                    foregroundColor: colors.onAccent,
                  ),
                  icon: const Icon(Icons.route),
                  label: const Text('Plan my commute'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              'Upcoming classes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () => setState(() => page = 1),
              child: const Text('View schedule →'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (next == null)
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: colors.soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Your class list is empty. Tap + to add your first class.',
              style: TextStyle(color: colors.muted),
              textAlign: TextAlign.center,
            ),
          ),
        ...upcoming.take(4).map(classTile),
      ],
    );
  }

  Widget tutorialCoach() {
    if (tutorialIndex == null) return const SizedBox.shrink();
    final steps = <(IconData, String, String, String)>[
      (
        Icons.dashboard_outlined,
        '1. Explore your dashboard',
        'This is your live day overview. Your next class and suggested leave time update from your schedule.',
        'Open Class Schedule',
      ),
      (
        Icons.add_circle_outline,
        '2. Try adding a class',
        'Tap the + button, enter a subject, then save it. Your dashboard and departure advice will update.',
        'Use the + button',
      ),
      (
        Icons.route_outlined,
        '3. Check your commute',
        'Use the Commute Planner to try walking, driving, or transit and compare the estimate.',
        'Continue to Settings',
      ),
      (
        Icons.settings_outlined,
        '4. Personalize your planner',
        'Review your campus and timing settings, then save when the values feel right.',
        'Finish tutorial',
      ),
    ];
    final step = steps[tutorialIndex!];
    return Container(
      key: const ValueKey('visual-tutorial'),
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(step.$1, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: skipTutorialStep,
                      child: const Text('Skip'),
                    ),
                    IconButton(
                      tooltip: 'Close tutorial',
                      onPressed: finishTutorial,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(step.$3),
                const SizedBox(height: 12),
                if (tutorialIndex == 1)
                  const Text('Waiting for you to save your first class')
                else
                  FilledButton.tonal(
                    onPressed: () {
                      if (tutorialIndex == 0) {
                        setState(() {
                          page = 1;
                          tutorialIndex = 1;
                        });
                      } else if (tutorialIndex == 2) {
                        setState(() {
                          page = 3;
                          tutorialIndex = 3;
                        });
                      } else {
                        finishTutorial();
                      }
                    },
                    child: Text(step.$4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: p,
    builder: (context, _) => PlannerShell(
      page: page,
      local: p.local,
      onPage: (i) => setState(() {
        page = i;
        if (tutorialIndex == 0 && i == 1) tutorialIndex = 1;
        if (tutorialIndex == 2 && i == 3) tutorialIndex = 3;
      }),
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
                child: Text(
                  '${days[manilaNow().weekday % 7]}, ${manilaNow().month}/${manilaNow().day}/${manilaNow().year} · ${clock(manilaNow())} PHT',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
          tutorialCoach(),
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
                  'travel': 'Journey minutes',
                  'prep': 'Preparation minutes',
                  'buffer': 'Arrival buffer minutes',
                }[key],
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < (key == 'travel' ? 1 : 0) || n > 480
                    ? 'Enter ${key == 'travel' ? 1 : 0}–480 minutes'
                    : null;
              },
              onSaved: (v) => draft[key] = int.parse(v!),
            ),
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
          'GPS runs only while the commute screen is open. Coordinates are sent to map and routing services to plan a journey, and are never stored in the student database. Route times are estimates without live traffic.',
        ),
      ],
    ),
  );
}
