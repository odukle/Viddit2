class CommentModel {
  final String id;
  String author;
  String body;
  int score;
  final double createdUtc;
  final List<CommentModel> replies;
  int userVote; // 1 = Upvote, -1 = Downvote, 0 = No Vote

  String get fullName => 't1_$id';

  CommentModel({
    required this.id,
    required this.author,
    required this.body,
    required this.score,
    required this.createdUtc,
    required this.replies,
    this.userVote = 0,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    final id = data['id'] ?? '';
    final author = data['author'] ?? 'unknown';
    final body = data['body'] ?? '';
    final score = data['score'] as int? ?? 0;
    final createdUtc = (data['created_utc'] as num?)?.toDouble() ?? 0.0;

    final replyList = <CommentModel>[];
    if (data['replies'] != null && data['replies'] is Map) {
      final repliesData = data['replies']['data'];
      if (repliesData != null && repliesData['children'] != null) {
        for (var child in repliesData['children']) {
          if (child['kind'] == 't1') {
            replyList.add(CommentModel.fromJson(child));
          }
        }
      }
    }

    int vote = 0;
    if (data['likes'] != null) {
      vote = (data['likes'] as bool) ? 1 : -1;
    }

    return CommentModel(
      id: id,
      author: author,
      body: body,
      score: score,
      createdUtc: createdUtc,
      replies: replyList,
      userVote: vote,
    );
  }
}
