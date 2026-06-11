class SubredditModel {
  final String title;
  final String displayNamePrefixed;
  final String description;
  final String headerImage;
  final String iconImage;
  final String bannerImage;
  final String subscribers;
  final String fullDescription;
  final bool? userIsSubscriber;

  SubredditModel({
    required this.title,
    required this.displayNamePrefixed,
    required this.description,
    required this.headerImage,
    required this.iconImage,
    required this.bannerImage,
    required this.subscribers,
    required this.fullDescription,
    this.userIsSubscriber,
  });

  factory SubredditModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};

    // Parse icons and banner URLs
    String icon = data['icon_img'] ?? '';
    if (icon.isEmpty || icon == 'null') {
      icon = data['community_icon'] ?? '';
    }
    icon = icon.replaceAll('amp;', '');

    final banner =
        (data['banner_background_image'] ?? '').replaceAll('amp;', '');
    final header = (data['header_img'] ?? '').replaceAll('amp;', '');

    // Format subscribers nicely
    final subscriberCount =
        data['subscribers'] != null ? data['subscribers'].toString() : '0';

    return SubredditModel(
      title: data['title'] ?? data['display_name'] ?? 'null',
      displayNamePrefixed: data['display_name_prefixed'] ?? 'r/unknown',
      description: data['public_description'] ?? '',
      headerImage: header,
      iconImage: icon,
      bannerImage: banner,
      subscribers: subscriberCount,
      fullDescription: data['description'] ?? '',
      userIsSubscriber: data['user_is_subscriber'] as bool?,
    );
  }

  factory SubredditModel.empty() {
    return SubredditModel(
      title: 'null',
      displayNamePrefixed: 'null',
      description: 'null',
      headerImage: 'null',
      iconImage: 'null',
      bannerImage: 'null',
      subscribers: 'null',
      fullDescription: 'null',
      userIsSubscriber: false,
    );
  }
}
