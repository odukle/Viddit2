class MultiRedditModel {
  final String name;
  final String displayName;
  final String iconUrl;
  final List<String> subreddits;

  MultiRedditModel({
    required this.name,
    required this.displayName,
    required this.iconUrl,
    required this.subreddits,
  });

  factory MultiRedditModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final subs = <String>[];
    if (data['subreddits'] != null) {
      for (var sub in data['subreddits']) {
        if (sub['name'] != null) {
          subs.add(sub['name']);
        }
      }
    }

    return MultiRedditModel(
      name: data['name'] ?? '',
      displayName: data['display_name'] ?? '',
      iconUrl: (data['icon_url'] ?? '').replaceAll('amp;', ''),
      subreddits: subs,
    );
  }
}
