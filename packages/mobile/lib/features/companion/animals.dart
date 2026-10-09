/// The companions a person can choose in Settings. Pure data: names, a line about each, and the colours that differ
/// from the dog's. Drawing them is `sprites.dart`.
library;

enum Animal { dog, unicorn, pigeon, hamster, cat, elephant }

class AnimalInfo {
  const AnimalInfo({required this.id, required this.name, required this.kind, required this.blurb, required this.says});
  final Animal id;

  /// What it is called.
  final String name;

  /// What it is.
  final String kind;
  final String blurb;

  /// What it says when tapped.
  final List<String> says;
}

const List<AnimalInfo> animals = [
  AnimalInfo(id: Animal.dog, name: 'Shiro', kind: 'Dog', blurb: 'Chases balls and digs up bones.', says: ['Woof!', 'Woof woof!', 'Arf!', 'Bork!']),
  AnimalInfo(id: Animal.unicorn, name: 'Stacy', kind: 'Unicorn', blurb: 'Sparkly, with a rainbow mane.', says: ['Neigh!', '✨ Sparkle!', 'Hehe~', 'Neeeigh!']),
  AnimalInfo(id: Animal.pigeon, name: 'Riti', kind: 'Pigeon', blurb: 'Bobs along and pecks at crumbs.', says: ['Coo coo!', 'Prrr-coo!', 'Coo!', 'Flap flap!']),
  AnimalInfo(id: Animal.hamster, name: 'Bubbly', kind: 'Hamster', blurb: 'Runs on a wheel, cheeks full of seeds.', says: ['Squeak!', 'Squeak squeak!', 'Nom nom!', 'Eek!']),
  AnimalInfo(id: Animal.cat, name: 'Tom', kind: 'Cat', blurb: 'Curious, with whiskers and a long tail.', says: ['Meow!', 'Mrrow?', 'Purrr…', 'Mew!']),
  AnimalInfo(id: Animal.elephant, name: 'Jumbo', kind: 'Elephant', blurb: 'Big ears, a gentle trunk.', says: ['Toot!', 'Pawoo!', 'Brrrap!', 'Splash!']),
];

const Animal defaultAnimal = Animal.dog;

/// Whether a stored value names one of the animals (exactly: 'cat', not 'Cat').
bool isAnimal(Object? v) => v is String && animals.any((a) => a.id.name == v);

AnimalInfo animalInfo(Animal id) => animals.firstWhere((a) => a.id == id, orElse: () => animals.first);

/// The colours each animal changes from the dog's palette (see `palette` in sprites.dart for what every letter is).
const Map<Animal, Map<String, int>> paletteOverrides = {
  Animal.dog: {},
  Animal.cat: {'f': 0x8d99ae, 'd': 0x5d6b85, 'c': 0xece8df, 't': 0xff8fa8},
  Animal.unicorn: {'f': 0xf7f3ff, 'd': 0xcfc5ec, 'c': 0xffd9f3, 'M': 0xff7ad9, 'N': 0x7ad7ff, 'H': 0xffd45a},
  Animal.elephant: {'f': 0xa3aec2, 'd': 0x7a869e, 'c': 0xd3dae6, 't': 0xaeb8ca, 'T': 0x7a869e},
  Animal.hamster: {'f': 0xf0b866, 'd': 0xd38c3a, 'c': 0xfff2d6, 't': 0xff9bb0, 'T': 0xe0708c},
  Animal.pigeon: {'f': 0xaab3c6, 'd': 0x727c94, 'c': 0xe6eaf2, 'M': 0x4fcfa6, 'N': 0xb57be0, 'y': 0xf2a73b, 'p': 0xff7f9c, 'u': 0xff9d3c},
};
