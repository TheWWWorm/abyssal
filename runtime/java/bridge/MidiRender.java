package bridge;

import javax.sound.midi.*;
import javax.sound.sampled.*;
import java.nio.file.*;
import java.util.*;

/** Render the supplied MIDI events with the JDK synthesizer, without a sound device. */
public final class MidiRender {
    record Event(long tick, int order, MidiMessage message) {}
    public static void main(String[] args) throws Exception {
        for (String arg : args) render(Path.of(arg));
    }
    static void render(Path source) throws Exception {
        Sequence sequence=MidiSystem.getSequence(source.toFile());
        Synthesizer synth=MidiSystem.getSynthesizer();
        AudioFormat format=new AudioFormat(44100,16,2,true,false);
        var open=synth.getClass().getMethod("openStream",AudioFormat.class,Map.class);
        try(AudioInputStream stream=(AudioInputStream)open.invoke(synth,format,Map.of())) {
            Receiver receiver=synth.getReceiver();
            List<Event> events=new ArrayList<>(); int order=0;
            for(Track track:sequence.getTracks()) for(int i=0;i<track.size();i++) {
                MidiEvent event=track.get(i);events.add(new Event(event.getTick(),order++,event.getMessage()));
            }
            events.sort(Comparator.comparingLong(Event::tick).thenComparingInt(Event::order));
            long previous=0;double micros=0;int tempo=500000;
            for(Event event:events) {
                long ticks=event.tick-previous;previous=event.tick;
                micros+=sequence.getDivisionType()==Sequence.PPQ
                    ? ticks*(double)tempo/sequence.getResolution()
                    : ticks*1_000_000.0/(sequence.getDivisionType()*sequence.getResolution());
                if(event.message instanceof MetaMessage meta) {
                    if(meta.getType()==0x51) {
                        byte[] d=meta.getData();tempo=((d[0]&255)<<16)|((d[1]&255)<<8)|(d[2]&255);
                    }
                } else receiver.send(event.message,(long)micros);
            }
            long frames=Math.max(1,(long)Math.ceil(micros*format.getFrameRate()/1_000_000));
            try(AudioInputStream limited=new AudioInputStream(stream,format,frames)) {
                AudioSystem.write(limited,AudioFileFormat.Type.WAVE,Path.of(source+".wav").toFile());
            }
            receiver.close();
            System.out.println("MIDI_RENDERED "+source.getFileName()+" "+micros/1_000_000+"s");
        } finally {synth.close();}
    }
}
