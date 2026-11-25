import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/design_tokens.dart';
import 'design_system.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

void showFeedback(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.surface,
              size: 20,
            ),
            SizedBox(width: 12),
            Expanded(child: Text(message.toString())),
          ],
        ),
        showCloseIcon: true,
        closeIconColor: Theme.of(context).colorScheme.surface,
      ),
    );
}

class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child, this.width = 720});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.auto_awesome_outlined,
  });
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ConexiaPalette.of(context).tinted,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 30,
            color: ConexiaPalette.of(context).primary,
          ),
        ),
        SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 340),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: ConexiaPalette.of(context).muted),
          ),
        ),
      ],
    ),
  );
}

class AsyncItems extends StatefulWidget {
  const AsyncItems({
    super.key,
    required this.load,
    required this.builder,
    this.empty = 'Nada por aqui ainda.',
  });
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  final String empty;
  @override
  State<AsyncItems> createState() => _AsyncItemsState();
}

class _AsyncItemsState extends State<AsyncItems> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    future = Future.sync(widget.load);
    future.ignore();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyState(
                    message: snapshot.error.toString(),
                    icon: Icons.cloud_off,
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      future = Future.sync(widget.load);
                      future.ignore();
                    }),
                    child: Text('Tentar novamente'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return ListSkeleton();
          }
          if (snapshot.data!.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(message: widget.empty),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) =>
                widget.builder(context, snapshot.data![index]),
          );
        },
      );
}

/// Keeps a long profile/family header usable on short displays and large text.
class HeaderBody extends StatelessWidget {
  const HeaderBody({super.key, required this.header, required this.body});
  final Widget header, body;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .55),
          child: SingleChildScrollView(child: header),
        ),
        Expanded(child: body),
      ],
    ),
  );
}
