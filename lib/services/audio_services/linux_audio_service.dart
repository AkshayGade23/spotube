import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mpris_service/mpris_service.dart';
import 'package:spotify/spotify.dart';
import 'package:spotube/models/spotube_track.dart';
import 'package:spotube/provider/proxy_playlist/proxy_playlist_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/loop_mode.dart';
import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/utils/type_conversion_utils.dart';

class LinuxAudioService {
  late final MPRIS mpris;
  final Ref ref;
  final ProxyPlaylistNotifier playlistNotifier;

  final subscriptions = <StreamSubscription>[];

  LinuxAudioService(this.ref, this.playlistNotifier) {
    MPRIS
        .create(
          busName: 'org.mpris.MediaPlayer2.spotube',
          identity: 'Spotube',
          desktopEntry: Platform.resolvedExecutable,
        )
        .then((value) => mpris = value)
        .then((_) {
      mpris.playbackStatus = MPRISPlaybackStatus.stopped;
      mpris.setEventHandler(MPRISEventHandler(
        loopStatus: (value) async {
          audioPlayer.setLoopMode(
            PlaybackLoopMode.fromMPRISLoopStatus(value),
          );
        },
        next: playlistNotifier.next,
        pause: audioPlayer.pause,
        play: audioPlayer.resume,
        playPause: () async {
          if (audioPlayer.isPlaying) {
            await audioPlayer.pause();
          } else {
            await audioPlayer.resume();
          }
        },
        seek: audioPlayer.seek,
        shuffle: audioPlayer.setShuffle,
        stop: playlistNotifier.stop,
        volume: audioPlayer.setVolume,
        previous: playlistNotifier.previous,
      ));

      final playerStateStream =
          audioPlayer.playerStateStream.listen((state) async {
        switch (state) {
          case AudioPlaybackState.buffering:
          case AudioPlaybackState.playing:
            mpris.playbackStatus = MPRISPlaybackStatus.playing;
            break;
          case AudioPlaybackState.paused:
            mpris.playbackStatus = MPRISPlaybackStatus.paused;
            break;
          case AudioPlaybackState.stopped:
          case AudioPlaybackState.completed:
            mpris.playbackStatus = MPRISPlaybackStatus.stopped;
            break;
          default:
            break;
        }
      });

      final positionStream = audioPlayer.positionStream.listen((pos) async {
        mpris.position = pos;
      });

      final durationStream =
          audioPlayer.durationStream.listen((duration) async {
        mpris.metadata = mpris.metadata.copyWith(length: duration);
      });

      subscriptions.addAll([
        playerStateStream,
        positionStream,
        durationStream,
      ]);
    });
  }

  Future<void> addTrack(Track track) async {
    mpris.metadata = MPRISMetadata(
      track is SpotubeTrack ? Uri.parse(track.ytUri) : Uri.parse(track.uri!),
      album: track.album?.name ?? "",
      albumArtist: [track.album?.artists?.first.name ?? ""],
      artUrl: Uri.parse(TypeConversionUtils.image_X_UrlString(
        track.album?.images ?? <Image>[],
        placeholder: ImagePlaceholder.albumArt,
      )),
      artist: track.artists?.map((e) => e.name!).toList(),
      contentCreated: DateTime.tryParse(track.album?.releaseDate ?? ""),
      discNumber: track.discNumber,
      length: track is SpotubeTrack
          ? track.ytTrack.duration!
          : Duration(milliseconds: track.durationMs!),
      title: track.name!,
      trackNumber: track.trackNumber,
    );
  }

  void dispose() {
    mpris.dispose();
    for (var element in subscriptions) {
      element.cancel();
    }
  }
}
