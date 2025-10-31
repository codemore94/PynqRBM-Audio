ManagedChannel channel =
    ManagedChannelBuilder.forAddress("192.168.1.50", 50051)
        .usePlaintext() // TODO: replace with TLS
        .build();

PynqAudioRBMGrpc.PynqAudioRBMBlockingStub blocking =
    PynqAudioRBMGrpc.newBlockingStub(channel);
PynqAudioRBMGrpc.PynqAudioRBMStub async =
    PynqAudioRBMGrpc.newStub(channel);

// Start session
SessionConfig cfg = SessionConfig.newBuilder()
    .setSampleRateHz(SAMPLE_RATE)
    .setFrameLen(FRAME_LEN)
    .setHopLen(FRAME_LEN) // simple demo
    .setChannels(1)
    .setNormalize(true)
    .setAuthToken("secret123")
    .build();
StartReply reply = blocking.startSession(cfg);
final String sessId = reply.getSessionId();

// Stream frames
StreamObserver<Logits> logitsObs = new StreamObserver<Logits>() {
  @Override public void onNext(Logits l) {
    // TODO: update UI: argmax(l.getValuesList())
  }
  @Override public void onError(Throwable t) { /* show error */ }
  @Override public void onCompleted() { /* stream ended */ }
};
StreamObserver<AudioFrame> frameObs = async.streamFrames(logitsObs);

// push frames in a background thread
new Thread(() -> {
  byte[] buf = new byte[FRAME_LEN];
  long ts = 0;
  for (;;) {
    int n = rec.read(buf, 0, buf.length);
    if (n <= 0) continue;
    AudioFrame f = AudioFrame.newBuilder()
        .setSessionId(sessId)
        .setPcm8(com.google.protobuf.ByteString.copyFrom(buf, 0, n))
        .setTimestamp(System.currentTimeMillis())
        .build();
    frameObs.onNext(f);
  }
}).start();
