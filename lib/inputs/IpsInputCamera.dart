import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:input_sheet/utils/IpsCameraButton.dart';
import 'package:input_sheet/utils/IpsMediaType.dart';
import 'package:input_sheet/utils/IpsModeCamera.dart';
import 'package:input_sheet/utils/colors.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quiver/async.dart';
import 'package:uuid/uuid.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'IpsInput.dart';

class IpsInputCamera extends IpsInput {
  Function(File, Uint8List) _onDone;
  File file;
  String url;
  double safePaddingTop;
  double height;
  IpsMediaType mediaType;
  IpsModeCamera cameraMode;
  ResolutionPreset resolution;
  VideoQuality compress;
  int timeRecordLimit;

  _IpsInputCameraState ipsInputCameraState;

  IpsInputCamera(
    this._onDone,
    this.mediaType,
    this.cameraMode,
    this.safePaddingTop, {
    this.file,
    this.url,
    this.height,
    this.compress,
    this.timeRecordLimit: 60,
    this.resolution: ResolutionPreset.high,
  }) {
    ipsInputCameraState = _IpsInputCameraState();
  }

  @override
  onDone() {
    if (_onDone != null) {
      ipsInputCameraState.callbackDone(pop: false);
    }
  }

  @override
  onCancel() {
    ipsInputCameraState.callbackDone(pop: false);
  }

  @override
  _IpsInputCameraState createState() => ipsInputCameraState;
}

class _IpsInputCameraState extends State<IpsInputCamera> {
  IpsMediaType mediaType;
  List<CameraDescription> cameras;
  CameraController controller;
  IpsModeCamera currentCamera = IpsModeCamera.BACK;
  File _selectedFile;
  //compress variabled
  bool compressing = false;

  void callbackDone({bool pop: true}) async {
    if (_selectedFile != null) {
      if (mediaType == IpsMediaType.VIDEO) {
        final thumbnailFile = await VideoCompress.getByteThumbnail(
          _selectedFile.path,
          quality: 50,
          position: -1,
        );
        this.widget._onDone(_selectedFile, thumbnailFile);
      } else {
        this.widget._onDone(_selectedFile, _selectedFile.readAsBytesSync());
      }
    } else {
      this.widget._onDone(null, null);
    }

    if (pop) {
      Navigator.pop(context);
    }
  }

  //start manage camera

  loadCamera() async {
    cameras = await availableCameras();
    controller = CameraController(
        cameras[currentCamera == IpsModeCamera.BACK ? 0 : 1],
        ResolutionPreset.low);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  discardMedia() async {
    if (await _selectedFile.exists()) {
      await _selectedFile.delete();
    }
    setState(() {
      compressing = false;
      _selectedFile = null;
      callbackDone(pop: true);
    });
  }

  switchCamera() async {
    if (cameras.length > 1) {
      int newCamera = currentCamera == IpsModeCamera.BACK ? 1 : 0;
      controller = CameraController(cameras[newCamera], ResolutionPreset.low);
      controller.initialize().then((_) {
        setState(() {
          currentCamera =
              newCamera == 0 ? IpsModeCamera.BACK : IpsModeCamera.FRONT;
        });
      });
    }
  }

  //stop manage camera

  //start manage photo

  capturePhoto() async {
    if (mediaType == IpsMediaType.PHOTO) {
      try {
        final uuid = Uuid();
        final directory = await getApplicationDocumentsDirectory();
        final String filename = "${directory.path}/${uuid.v4()}.jpg";
        await controller.takePicture(filename);
        File localFile = new File(filename);
        setState(() {
          _selectedFile = localFile;
        });
      } catch (error) {
        if (error is CameraException) {
          print("Camera Error = $error");
        } else if (error is FileSystemException) {
          print("File System Error = $error");
        } else {
          print(error);
        }
      }
    }
  }

  //stop manage photo

  //start manage video

  VideoPlayerController videoController;
  bool playingVideo = false;
  String videoFilename;
  String remainingRecord = "";
  CountdownTimer timer;

  recordVideo() async {
    if (mediaType == IpsMediaType.VIDEO &&
        (controller.value?.isRecordingVideo ?? false) == false) {
      try {
        final uuid = Uuid();
        final directory = await getApplicationDocumentsDirectory();
        videoFilename = "${directory.path}/${uuid.v4()}.mp4";
        await controller.prepareForVideoRecording().then((_) {
          controller.startVideoRecording(videoFilename);
          setState(() {
            remainingRecord = "${this.widget.timeRecordLimit} Sec";
          });
          initCountdown();
        });
      } catch (error) {
        if (error is CameraException) {
          print("Camera Error = $error");
        } else if (error is FileSystemException) {
          print("File System Error = $error");
        } else {
          print(error);
        }
      }
    }
  }

  stopRecord() async {
    if (mediaType == IpsMediaType.VIDEO &&
        (controller.value?.isRecordingVideo ?? false) == true) {
      if (!mounted) return;
      timer?.cancel();
      try {
        await controller.stopVideoRecording();
      } catch (_error) {}
      File resolveFile;
      if (this.widget.compress != null) {
        setState(() {
          compressing = true;
        });
        MediaInfo mediaInfo = await VideoCompress.compressVideo(
          videoFilename,
          quality: VideoQuality.LowQuality,
          deleteOrigin: true, // It's false by default
        );
        setState(() {
          compressing = false;
        });
        resolveFile = mediaInfo.file;
      } else {
        resolveFile = new File(videoFilename);
      }
      if (!mounted) return;
      setState(() {
        _selectedFile = resolveFile;
        remainingRecord = "";
        videoController = VideoPlayerController.file(resolveFile)
          ..setVolume(1.0)
          ..addListener(listenerVideo)
          ..initialize().then((_) => videoController?.play());
      });
    }
  }

  void playVideo() {
    if (videoController?.value?.isPlaying == false ?? false) {
      if ((videoController?.value?.position ?? 0) ==
          (videoController?.value?.duration ?? 0)) {
        videoController?.seekTo(new Duration(seconds: 0));
      }
      videoController?.play();
    }
  }

  void pauseVideo() {
    if (videoController?.value?.isPlaying ?? false) {
      videoController?.pause();
    }
  }

  void stopVideo() {
    videoController?.pause();
    videoController?.seekTo(new Duration(seconds: 0));
  }

  void listenerVideo() async {
    setState(() {
      playingVideo = videoController?.value?.isPlaying ?? false;
    });
  }

  void initCountdown() {
    timer?.cancel();
    timer = CountdownTimer(
        Duration(seconds: this.widget.timeRecordLimit), Duration(seconds: 1));
    timer.listen((data) {})
      ..onData((CountdownTimer data) {
        setState(() {
          remainingRecord = "${data.remaining.inSeconds} Sec";
        });
      })
      ..onDone(() {
        stopRecord();
      });
  }

  // stop video manager

  @override
  initState() {
    mediaType = this.widget.mediaType;
    currentCamera = this.widget.cameraMode;
    loadCamera();
    if (this.widget.file != null) {
      _selectedFile = this.widget.file;
      remainingRecord = "";
      videoController = VideoPlayerController.file(_selectedFile)
        ..setVolume(1.0)
        ..addListener(listenerVideo)
        ..initialize().then((_) => videoController?.play());
    }
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    videoController?.dispose();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: this.widget.height ??
          (MediaQuery.of(context).size.height -
              this.widget.safePaddingTop -
              45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              height: double.maxFinite,
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Expanded(
                    child: _selectedFile == null
                        ? Stack(
                            children: <Widget>[
                              Positioned(
                                left: 0,
                                top: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  color: Colors.black,
                                  child: Visibility(
                                    visible:
                                        (controller?.value?.isInitialized ??
                                                false) ==
                                            true,
                                    replacement: Container(
                                      alignment: Alignment.center,
                                      child: Text(
                                        "Camera is not initialized yet",
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    child: Visibility(
                                      visible: compressing != true,
                                      replacement: Container(
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: <Widget>[
                                            SizedBox(
                                              width: 21,
                                              height: 21,
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              "Proccessing...",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: AspectRatio(
                                        aspectRatio:
                                            controller.value.aspectRatio,
                                        child: CameraPreview(controller),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Visibility(
                                visible: compressing != true,
                                replacement: Positioned(
                                  bottom: 50,
                                  left: 0,
                                  right: 0,
                                  child: Container(),
                                ),
                                child: Visibility(
                                  visible: mediaType == IpsMediaType.PHOTO,
                                  replacement: Positioned(
                                    bottom: 50,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: <Widget>[
                                          Visibility(
                                            visible: !(controller
                                                    .value?.isRecordingVideo ??
                                                false),
                                            child: IpsCameraButton(
                                              size: 40,
                                              onPress: () =>
                                                  Navigator.pop(context),
                                              icon: Icon(
                                                FeatherIcons.arrowLeft,
                                                size: 16,
                                                color: IpsColors.white,
                                              ),
                                            ),
                                          ),
                                          Column(
                                            children: <Widget>[
                                              IpsCameraButton(
                                                onPress: (controller.value
                                                            ?.isRecordingVideo ??
                                                        false)
                                                    ? stopRecord
                                                    : recordVideo,
                                                color: IpsColors.red,
                                                icon: Icon(
                                                  (controller.value
                                                              ?.isRecordingVideo ??
                                                          false)
                                                      ? FeatherIcons.square
                                                      : FeatherIcons.video,
                                                  size: 16,
                                                  color: IpsColors.white,
                                                ),
                                              ),
                                              SizedBox(
                                                  height: (controller.value
                                                              ?.isRecordingVideo ??
                                                          false)
                                                      ? 10
                                                      : 0),
                                              Visibility(
                                                visible: (controller.value
                                                        ?.isRecordingVideo ??
                                                    false),
                                                child: Text(
                                                  remainingRecord,
                                                  style: TextStyle(
                                                    color: IpsColors.white,
                                                    fontSize: 12,
                                                    fontFamily: 'Montserrat',
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                          Visibility(
                                            visible: !(controller
                                                    .value?.isRecordingVideo ??
                                                false),
                                            child: IpsCameraButton(
                                              size: 40,
                                              onPress: switchCamera,
                                              icon: Icon(
                                                FeatherIcons.copy,
                                                size: 16,
                                                color: IpsColors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  child: Positioned(
                                    bottom: 50,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: <Widget>[
                                          IpsCameraButton(
                                            size: 40,
                                            onPress: () =>
                                                Navigator.pop(context),
                                            icon: Icon(
                                              FeatherIcons.arrowLeft,
                                              size: 16,
                                              color: IpsColors.white,
                                            ),
                                          ),
                                          IpsCameraButton(
                                            onPress: capturePhoto,
                                            color: IpsColors.red,
                                            icon: Icon(
                                              FeatherIcons.camera,
                                              size: 16,
                                              color: IpsColors.white,
                                            ),
                                          ),
                                          IpsCameraButton(
                                            size: 40,
                                            onPress: switchCamera,
                                            icon: Icon(
                                              FeatherIcons.copy,
                                              size: 16,
                                              color: IpsColors.white,
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Stack(
                            children: <Widget>[
                              mediaType == IpsMediaType.PHOTO
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        image: DecorationImage(
                                          image: FileImage(_selectedFile),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                  : Positioned(
                                      left: -5,
                                      top: -5,
                                      right: -5,
                                      bottom: -5,
                                      child: Container(
                                        color: Colors.black,
                                        child: videoController
                                                    ?.value?.initialized ??
                                                false == true
                                            ? AspectRatio(
                                                aspectRatio: videoController
                                                    ?.value?.aspectRatio,
                                                child: VideoPlayer(
                                                    videoController),
                                              )
                                            : Container(),
                                      ),
                                    ),
                              Positioned(
                                bottom: 50,
                                left: 0,
                                right: 0,
                                child: Visibility(
                                  visible: mediaType == IpsMediaType.PHOTO,
                                  replacement: Container(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: <Widget>[
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: discardMedia,
                                          icon: Icon(
                                            FeatherIcons.trash,
                                            size: 16,
                                            color: IpsColors.white,
                                          ),
                                        ),
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: playingVideo ?? false
                                              ? pauseVideo
                                              : playVideo,
                                          icon: playingVideo ?? false
                                              ? Icon(
                                                  FeatherIcons.pause,
                                                  size: 16,
                                                  color: IpsColors.white,
                                                )
                                              : Icon(
                                                  FeatherIcons.play,
                                                  size: 16,
                                                  color: IpsColors.white,
                                                ),
                                        ),
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: stopVideo,
                                          icon: Icon(
                                            FeatherIcons.skipBack,
                                            size: 16,
                                            color: IpsColors.white,
                                          ),
                                        ),
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: () => callbackDone(),
                                          icon: Icon(
                                            FeatherIcons.check,
                                            size: 16,
                                            color: IpsColors.white,
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                  child: Container(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: <Widget>[
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: discardMedia,
                                          icon: Icon(
                                            FeatherIcons.trash,
                                            size: 16,
                                            color: IpsColors.white,
                                          ),
                                        ),
                                        IpsCameraButton(
                                          size: 40,
                                          onPress: () => callbackDone(),
                                          icon: Icon(
                                            FeatherIcons.check,
                                            size: 16,
                                            color: IpsColors.white,
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}