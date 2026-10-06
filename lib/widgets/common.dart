import 'package:flutter/material.dart';
import '../state/app_state.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

void showFeedback(BuildContext context, Object message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
}

class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child, this.width = 720});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.auto_awesome_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text(message, textAlign: TextAlign.center)]));
}

class AsyncItems extends StatefulWidget {
  const AsyncItems({super.key, required this.load, required this.builder, this.empty = 'Nada por aqui ainda.'});
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  final String empty;
  @override
  State<AsyncItems> createState() => _AsyncItemsState();
}
class _AsyncItemsState extends State<AsyncItems> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() { super.initState(); future = widget.load(); }
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(future: future, builder: (context, snapshot) {
    if (snapshot.hasError) return Column(mainAxisSize: MainAxisSize.min, children: [EmptyState(message: snapshot.error.toString(), icon: Icons.cloud_off), TextButton(onPressed: () => setState(() => future = widget.load()), child: const Text('Tentar novamente'))]);
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    if (snapshot.data!.isEmpty) return EmptyState(message: widget.empty);
    return ListView(children: snapshot.data!.map((row) => widget.builder(context, row)).toList());
  });
}
