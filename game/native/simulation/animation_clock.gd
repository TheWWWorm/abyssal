extends RefCounted
## Elapsed-time frame sampling without discarding overshoot at loop boundaries.
var last_frame:=0
var start_frame:=0
var end_frame:=0
var frame:=0
var frame_ms:=1
var started_at:=-1
var mode:=2
var playing:=false
func configure(last: int,milliseconds: int) -> void:
 last_frame=maxi(0,last);frame_ms=maxi(1,milliseconds);set_range(0,last_frame);playing=last_frame>0
func set_range(first: int,last: int) -> void:
 start_frame=clampi(first,0,last_frame);end_frame=clampi(last,start_frame,last_frame)
 frame=start_frame;started_at=-1
func play(new_mode: int) -> void:mode=new_mode;frame=start_frame;started_at=-1;playing=last_frame>0
func advance(absolute_ms: int) -> void:
 if not playing:return
 if started_at<0:started_at=absolute_ms
 var elapsed:=maxi(0,absolute_ms-started_at)/frame_ms
 var count:=end_frame-start_frame+1
 if mode==2:frame=start_frame+elapsed%count
 else:
  frame=mini(end_frame,start_frame+elapsed)
  if elapsed>=count:playing=false
func sample() -> int:return end_frame-(frame-start_frame) if mode==3 else frame
