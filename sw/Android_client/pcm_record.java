int SAMPLE_RATE = 16000;
int FRAME_LEN = 256;

AudioRecord rec = new AudioRecord(
    MediaRecorder.AudioSource.MIC,
    SAMPLE_RATE,
    AudioFormat.CHANNEL_IN_MONO,
    AudioFormat.ENCODING_PCM_8BIT,
    FRAME_LEN * 4);

rec.startRecording();
byte[] buf = new byte[FRAME_LEN];
