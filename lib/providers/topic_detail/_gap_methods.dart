part of '../topic_detail_provider.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

/// Gaps 相关方法（拉黑用户的帖子加载）
extension GapMethods on TopicDetailNotifier {
  /// 加载某个帖子前面的 gap 帖子
  Future<void> fillGapBefore(int postId) => _fillGap(postId, before: true);

  /// 加载某个帖子后面的 gap 帖子
  Future<void> fillGapAfter(int postId) => _fillGap(postId, before: false);

  Future<void> _fillGap(int postId, {required bool before}) async {
    final currentDetail = state.value;
    if (currentDetail == null) return;

    final gaps = currentDetail.postStream.gaps;
    if (gaps == null) return;

    final gapPostIds = (before ? gaps.before : gaps.after)[postId];
    if (gapPostIds == null || gapPostIds.isEmpty) return;

    try {
      final service = ref.read(discourseServiceProvider);
      final newPostStream = await service.getPosts(arg.topicId, gapPostIds);

      if (!ref.mounted) return;
      final updatedDetail = state.value;
      if (updatedDetail == null) return;

      final currentPosts = updatedDetail.postStream.posts;
      final existingIds = currentPosts.map((p) => p.id).toSet();
      final newPosts = newPostStream.posts.where((p) => !existingIds.contains(p.id)).toList();

      if (newPosts.isEmpty) {
        // 即使没有新帖子也要移除 gap 条目
        _removeGapEntry(
          updatedDetail,
          before: before ? postId : null,
          after: before ? null : postId,
        );
        return;
      }

      state = AsyncValue.data(revealGapInDetail(
        updatedDetail,
        postId,
        before: before,
        gapPostIds: gapPostIds,
        newPosts: newPosts,
      ));
    } catch (e) {
      debugPrint('[TopicDetail] fillGap${before ? 'Before' : 'After'}($postId) 失败: $e');
    }
  }

  /// 把某个已展开的 gap 重新折叠：只在本地把展开出来的楼层拿掉，
  /// 原来被跳过的楼层 id 放回 gaps，不发任何请求。
  void collapseGap(int postId, {required bool before}) {
    final currentDetail = state.value;
    if (currentDetail == null) return;
    final collapsed = collapseGapInDetail(currentDetail, postId, before: before);
    if (collapsed != null) state = AsyncValue.data(collapsed);
  }

  /// 移除 gap 条目的辅助方法
  void _removeGapEntry(TopicDetail detail, {int? before, int? after}) {
    final currentGaps = detail.postStream.gaps;
    if (currentGaps == null) return;

    final newBefore = Map<int, List<int>>.from(currentGaps.before);
    final newAfter = Map<int, List<int>>.from(currentGaps.after);

    if (before != null) newBefore.remove(before);
    if (after != null) newAfter.remove(after);

    final updatedGaps = PostStreamGaps(
      before: newBefore,
      after: newAfter,
      revealedBefore: currentGaps.revealedBefore,
      revealedAfter: currentGaps.revealedAfter,
    );

    state = AsyncValue.data(detail.copyWith(
      postStream: PostStream(
        posts: detail.postStream.posts,
        stream: detail.postStream.stream,
        gaps: updatedGaps.isEmpty ? null : updatedGaps,
      ),
    ));
  }

  /// 展开隐藏帖子的原始内容
  Future<void> expandHiddenPost(int postId) async {
    try {
      final service = ref.read(discourseServiceProvider);
      final cooked = await service.getPostCooked(postId);
      if (!ref.mounted) return;
      _updatePostById(postId, (post) => post.copyWith(
        cooked: cooked,
        cookedHidden: false,
      ));
    } catch (e) {
      debugPrint('[TopicDetail] expandHiddenPost($postId) 失败: $e');
    }
  }
}

/// 把 gap 里取到的楼层并进详情：插到锚点楼层前面（[before]）或后面，
/// 去掉对应的 gap 条目，并记下展开记录供 [collapseGapInDetail] 还原。
TopicDetail revealGapInDetail(
  TopicDetail detail,
  int postId, {
  required bool before,
  required List<int> gapPostIds,
  required List<Post> newPosts,
}) {
  final currentPosts = detail.postStream.posts;
  // 找到目标帖子的位置，新帖子插到它前面（before）或后面（after）
  final targetIndex = currentPosts.indexWhere((p) => p.id == postId);
  final mergedPosts = [...currentPosts];
  if (targetIndex != -1) {
    mergedPosts.insertAll(before ? targetIndex : targetIndex + 1, newPosts);
  } else {
    mergedPosts.addAll(newPosts);
  }
  mergedPosts.sort((a, b) => a.postNumber.compareTo(b.postNumber));

  // 更新 stream
  final currentStream = detail.postStream.stream;
  final existingStreamIds = currentStream.toSet();
  final newStreamIds = newPosts.map((p) => p.id).where((id) => !existingStreamIds.contains(id)).toList();
  final mergedStream = [...currentStream, ...newStreamIds];

  // 移除已加载的 gap 条目，并记下展开记录，供「收起」还原
  final currentGaps = detail.postStream.gaps;
  final newBefore = Map<int, List<int>>.from(currentGaps?.before ?? {});
  final newAfter = Map<int, List<int>>.from(currentGaps?.after ?? {});
  final newRevealedBefore = Map<int, RevealedGap>.from(currentGaps?.revealedBefore ?? {});
  final newRevealedAfter = Map<int, RevealedGap>.from(currentGaps?.revealedAfter ?? {});
  final revealed = RevealedGap(
    gapPostIds: gapPostIds,
    insertedPostIds: newPosts.map((p) => p.id).toList(),
    addedStreamIds: newStreamIds,
  );
  if (before) {
    newBefore.remove(postId);
    newRevealedBefore[postId] = revealed;
  } else {
    newAfter.remove(postId);
    newRevealedAfter[postId] = revealed;
  }
  final updatedGaps = PostStreamGaps(
    before: newBefore,
    after: newAfter,
    revealedBefore: newRevealedBefore,
    revealedAfter: newRevealedAfter,
  );
  return detail.copyWith(
    postStream: PostStream(
      posts: mergedPosts,
      stream: mergedStream,
      gaps: updatedGaps.isEmpty ? null : updatedGaps,
    ),
  );
}

/// 把某个已展开的 gap 重新折叠：只在本地把展开出来的楼层拿掉，
/// 原来被跳过的楼层 id 放回 gaps，不发任何请求。没有展开记录返回 null。
TopicDetail? collapseGapInDetail(
  TopicDetail detail,
  int postId, {
  required bool before,
}) {
  final gaps = detail.postStream.gaps;
  if (gaps == null) return null;
  final revealed = (before ? gaps.revealedBefore : gaps.revealedAfter)[postId];
  if (revealed == null) return null;

  final removeIds = revealed.insertedPostIds.toSet();
  final removeStreamIds = revealed.addedStreamIds.toSet();
  final posts = detail.postStream.posts.where((p) => !removeIds.contains(p.id)).toList();
  final stream = detail.postStream.stream.where((id) => !removeStreamIds.contains(id)).toList();

  final newBefore = Map<int, List<int>>.from(gaps.before);
  final newAfter = Map<int, List<int>>.from(gaps.after);
  final newRevealedBefore = Map<int, RevealedGap>.from(gaps.revealedBefore);
  final newRevealedAfter = Map<int, RevealedGap>.from(gaps.revealedAfter);
  if (before) {
    newBefore[postId] = revealed.gapPostIds;
    newRevealedBefore.remove(postId);
  } else {
    newAfter[postId] = revealed.gapPostIds;
    newRevealedAfter.remove(postId);
  }
  return detail.copyWith(
    postStream: PostStream(
      posts: posts,
      stream: stream,
      gaps: PostStreamGaps(
        before: newBefore,
        after: newAfter,
        revealedBefore: newRevealedBefore,
        revealedAfter: newRevealedAfter,
      ),
    ),
  );
}
