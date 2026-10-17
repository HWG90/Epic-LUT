"""Snapshot publication tolerates concurrent creators without partial files."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
harness = r"""
public static class SnapshotPublishRace {
 public static void Run(string folder) {
  System.IO.Directory.CreateDirectory(folder);
  var write=typeof(EpicOriginalReader).GetMethod("Write",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Static);
  var errors=new System.Collections.Concurrent.ConcurrentQueue<System.Exception>();
  for(int round=0;round<20;round++) {
   string path=System.IO.Path.Combine(folder,"cache-"+round+".dds");
   var start=new System.Threading.ManualResetEventSlim(false);
   var threads=new System.Threading.Thread[12];
   for(int i=0;i<threads.Length;i++) {
    int id=i;threads[i]=new System.Threading.Thread(()=>{try {
     var bytes=new byte[65536];for(int b=0;b<bytes.Length;b++)bytes[b]=(byte)(id+1);
     start.Wait();write.Invoke(null,new object[]{path,new byte[0],bytes});
    }catch(System.Exception e){errors.Enqueue(e);}});threads[i].Start();
   }
   start.Set();foreach(var thread in threads)thread.Join();
   if(!errors.IsEmpty)throw new System.Exception("Concurrent snapshot write failed: "+errors.ToArray()[0].ToString());
   var result=System.IO.File.ReadAllBytes(path);
   if(result.Length!=65536)throw new System.Exception("Partial snapshot");
   foreach(byte b in result)if(b!=result[0])throw new System.Exception("Mixed snapshot bytes");
  }
  if(System.IO.Directory.GetFiles(folder,"*.pending").Length!=0)throw new System.Exception("Pending file leaked");
 }
}
"""
with tempfile.TemporaryDirectory(prefix='epic-snapshot-race-') as temp:
    folder=Path(temp)
    source=folder/'race.cs'
    source.write_text((ROOT/'tools/original_snapshots.cs').read_text()+harness)
    script=folder/'run.ps1'
    script.write_text("$ErrorActionPreference='Stop'\nAdd-Type -Path '"+str(source)+"'\n[SnapshotPublishRace]::Run('"+str(folder/'output')+"')\n")
    subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-File',str(script)],check=True,timeout=60)
print('PASS concurrent snapshot publication: 240 writers, complete final bytes and no pending-file leaks')
