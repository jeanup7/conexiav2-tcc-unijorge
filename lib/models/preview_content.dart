import '../models/models.dart';

/// User-supplied assets are bundled only as clearly identified preview content.
const previewPublications = <Publication>[
  Publication(
    id: 'preview-1', userId: 'preview-luffy', author: 'luffy',
    text: 'Um novo dia, uma nova aventura. Quem vem comigo? ☀️\n#anime #onepiece #aventura',
    likes: 128, liked: false, assetImage: 'assets/feed/luffy.jpg',
  ),
  Publication(
    id: 'preview-2', userId: 'preview-peter', author: 'peter.parker',
    text: 'Entre uma aula e outra, sempre cabe um sorriso. 🕷️\n#peterparker #cinema',
    likes: 96, liked: false, assetImage: 'assets/feed/peter_parker.jpg',
  ),
  Publication(
    id: 'preview-3', userId: 'preview-spider', author: 'amigodavizinhanca',
    text: 'Meu estilo favorito de herói nos quadrinhos. Qual é o seu? ❤️\n#spiderman #quadrinhos #arte',
    likes: 214, liked: false, assetImage: 'assets/feed/spider_man.webp',
  ),
  Publication(
    id: 'preview-4', userId: 'preview-bahia', author: 'shikamaru.tricolor',
    text: 'Modo ninja, coração tricolor. Bora, Bahia! 💙❤️\n#bahia #anime #criatividade',
    likes: 187, liked: false, assetImage: 'assets/feed/shikamaru_bahia.png',
  ),
];
