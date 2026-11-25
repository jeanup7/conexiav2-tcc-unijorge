import 'package:flutter/material.dart';

import 'profile_avatar.dart';

class ProfileHeading extends StatelessWidget {
  const ProfileHeading({
    super.key,
    required this.name,
    required this.bio,
    required this.private,
    this.media,
    this.image,
    this.count,
    this.hasMore = false,
  });
  final String name, bio;
  final bool private, hasMore;
  final String? media;
  final ImageProvider? image;
  final int? count;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            media: media,
            image: image,
            radius: 32,
            label: 'Foto de $name',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  private ? 'Perfil privado' : 'Perfil público',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      if (bio.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(bio, style: Theme.of(context).textTheme.bodyMedium),
      ],
      const SizedBox(height: 20),
      Semantics(
        excludeSemantics: true,
        label: count == null
            ? 'Carregando publicações'
            : '$count${hasMore ? " ou mais" : ""} publicações',
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Text(
              count == null ? '—' : '$count${hasMore ? "+" : ""}',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              hasMore ? 'publicações carregadas' : 'publicações',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ],
  );
}

class FirstPublication extends StatelessWidget {
  const FirstPublication({super.key, required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.note_add_outlined,
          size: 38,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Seu caderno começa aqui',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Uma ideia, uma descoberta ou um registro do seu dia.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Criar primeira publicação'),
        ),
      ],
    ),
  );
}
