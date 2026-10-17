// Read-only DSAR/DSAA reader. Format research: CowboyBingus (vendor/LICENSE).
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
public sealed class EpicOriginalReader : IDisposable {
 static int owner; static string progress; static Stopwatch pulse=Stopwatch.StartNew();
 static Stopwatch health=Stopwatch.StartNew();static bool healthChecked;
 static void Check(){
  if(healthChecked&&health.ElapsedMilliseconds<250)return;healthChecked=true;health.Restart();
  if(progress!=null&&File.Exists(progress+".cancel"))throw new Exception("Snapshot canceled");
  if(owner!=0){string heartbeat=Path.Combine(Path.GetDirectoryName(progress),"owner-heartbeat.txt");
   if(!File.Exists(heartbeat)||(DateTime.UtcNow-File.GetLastWriteTimeUtc(heartbeat)).TotalSeconds>15)throw new Exception("Game heartbeat expired");
   try{int recorded;if(int.TryParse(File.ReadAllText(heartbeat).Trim(),out recorded)&&recorded!=owner)throw new Exception("Game owner changed");}catch(IOException){}
  }
 }
 static void Pulse(string text){Check();if(progress!=null&&pulse.ElapsedMilliseconds>500){File.WriteAllText(progress,text);pulse.Restart();}}
 static uint U(byte[] b,int p){if(p<0||p>b.Length-4)throw new Exception("Truncated integer");return BitConverter.ToUInt32(b,p);}
 static ulong Q(byte[] b,int p){if(p<0||p>b.Length-8)throw new Exception("Truncated offset");return BitConverter.ToUInt64(b,p);}
 static int N(ulong n){if(n>int.MaxValue)throw new Exception("Oversized field");return (int)n;}
 static byte[] Slice(byte[] b,int p,int n){if(p<0||n<0||p>b.Length-n)throw new Exception("Truncated data");var r=new byte[n];Buffer.BlockCopy(b,p,r,0,n);return r;}
 static byte[] Lz(byte[] s,int size){var o=new byte[size];int p=0,k=0;while(p<s.Length){Check();int token=s[p++],n=token>>4;if(n==15){int x;do{if(p>=s.Length)throw new Exception("LZ4 length");x=s[p++];n=checked(n+x);}while(x==255);}if(n>s.Length-p||n>size-k)throw new Exception("LZ4 literal bounds");Buffer.BlockCopy(s,p,o,k,n);p+=n;k+=n;if(p==s.Length)break;if(p>s.Length-2)throw new Exception("LZ4 offset");int back=s[p]|s[p+1]<<8;p+=2;if(back==0||back>k)throw new Exception("LZ4 distance");n=(token&15)+4;if((token&15)==15){int x;do{if(p>=s.Length)throw new Exception("LZ4 length");x=s[p++];n=checked(n+x);}while(x==255);}if(n>size-k)throw new Exception("LZ4 match bounds");for(int i=0;i<n;i++){o[k]=o[k-back];k++;}}if(k!=size)throw new Exception("Short LZ4 block");return o;}
 sealed class Bundle : IDisposable {
  FileStream f;byte[] table;int count;Dictionary<int,byte[]> cache=new Dictionary<int,byte[]>();
  public ulong Length;
  public Bundle(string path){f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite);try{var h=Raw(0,32);if(Encoding.ASCII.GetString(h,0,4)!="DSAR")throw new Exception("Not DSAR");count=N(U(h,8));if(count<1||count>1000000)throw new Exception("Chunk count");table=Raw(32,checked(count*32));ulong last=0;for(int i=0;i<count;i++){ulong start=Q(table,i*32);if(i>0&&start<=last)throw new Exception("Chunk order");last=start;}Length=checked(last+U(table,(count-1)*32+16));}catch{f.Dispose();throw;}}
  byte[] Raw(ulong at,int n){Check();if(n<0||at>(ulong)f.Length||((ulong)n)>(ulong)f.Length-at)throw new Exception("Bundle bounds");f.Position=(long)at;var b=new byte[n];int p=0;while(p<n){Check();int got=f.Read(b,p,Math.Min(65536,n-p));if(got==0)throw new Exception("Short read");p+=got;}return b;}
  public byte[] Read(ulong at,int n){if(n<0||n>128*1024*1024||at>Length||((ulong)n)>Length-at)throw new Exception("Logical bounds");var output=new byte[n];int written=0;while(written<n){int low=0,high=count-1;while(low<=high){int mid=(low+high)/2;if(Q(table,mid*32)<=at)low=mid+1;else high=mid-1;}if(high<0)throw new Exception("Missing chunk");int pos=high*32;ulong start=Q(table,pos),packed=Q(table,pos+8);int length=N(U(table,pos+16)),packedSize=N(U(table,pos+20));if(length>64*1024*1024||packedSize>64*1024*1024||at>=start+(ulong)length)throw new Exception("Chunk bounds");int skip=N(at-start),take=Math.Min(n-written,length-skip);byte[] chunk;if(table[pos+24]==0)chunk=Raw(packed+(ulong)skip,take);else if(table[pos+24]==3){if(!cache.TryGetValue(high,out chunk)){if(cache.Count>=3)cache.Clear();chunk=Lz(Raw(packed,packedSize),length);cache[high]=chunk;}chunk=Slice(chunk,skip,take);}else throw new Exception("Unsupported compression");Buffer.BlockCopy(chunk,0,output,written,take);written+=take;at+=(ulong)take;}return output;}
  public void Dispose(){f.Dispose();}
 }
 sealed class Entry {public ulong Total,At;public int Count;}
 Bundle index;byte[] data;string folder;string[] names;Dictionary<string,Entry> entries=new Dictionary<string,Entry>();Dictionary<int,Bundle> bundles=new Dictionary<int,Bundle>();
 string Name(int at){int end=at;while(end<data.Length&&end-at<256&&data[end]!=0)end++;if(at<0||end>=data.Length||end-at>=256)throw new Exception("Invalid name");return Encoding.ASCII.GetString(data,at,end-at);}
 public EpicOriginalReader(string path){folder=path;index=new Bundle(Path.Combine(path,"bundles.nxa"));try{data=index.Read(0,N(index.Length));if(Encoding.ASCII.GetString(data,0,4)!="DSAA")throw new Exception("Not DSAA");int b=N(U(data,12)),n=N(U(data,16));if(b<1||b>256||n<1||n>1000000)throw new Exception("Index count");names=new string[b];for(int i=0;i<b;i++){names[i]=Name(N(U(data,checked(24+n*24+i*4))));if(Path.GetFileName(names[i])!=names[i]||names[i].Contains("/")||names[i].Contains("\\"))throw new Exception("Invalid bundle name");}for(int i=0;i<n;i++){int p=checked(24+i*24);entries.Add(Name(N(U(data,p+8))),new Entry{Total=Q(data,p),Count=N(U(data,p+12)),At=Q(data,p+16)});}}catch{index.Dispose();throw;}}
 byte[] Read(string name,ulong at,int size){Entry e;if(!entries.TryGetValue(name,out e)||size<0||at>e.Total||((ulong)size)>e.Total-at||e.Count<1||e.Count>1000000)throw new Exception("Archive bounds: "+name);var spans=index.Read(e.At,checked(e.Count*16));var result=new byte[size];int wrote=0;while(wrote<size){int low=0,high=e.Count-1;while(low<=high){int mid=(low+high)/2;if(U(spans,mid*16)<=at)low=mid+1;else high=mid-1;}if(high<0)throw new Exception("Missing archive span");int p=high*16;ulong start=U(spans,p),end=high+1<e.Count?U(spans,p+16):e.Total;if(end<=at)throw new Exception("Archive span order");int take=(int)Math.Min((ulong)(size-wrote),end-at);int number=spans[p+15];if(number>=names.Length)throw new Exception("Bundle number");Bundle bundle;if(!bundles.TryGetValue(number,out bundle)){bundle=new Bundle(Path.Combine(folder,names[number]));bundles[number]=bundle;}var bytes=bundle.Read(U(spans,p+8)+at-start,take);Buffer.BlockCopy(bytes,0,result,wrote,take);wrote+=take;at+=(ulong)take;}return result;}
 static double Half(ushort h){int sign=(h>>15)==0?1:-1,e=(h>>10)&31,m=h&1023;if(e==31)throw new Exception("Nonfinite LUT");return sign*(e==0?Math.Pow(2,-24)*m:Math.Pow(2,e-15)*(1+m/1024.0));}
 const long LooseBudget=64L*1024*1024,LooseRowBudget=1000000;
 const ulong TextureType=0xcd4238c6a0c69e32UL;
 sealed class Lut {
  public string Hash,Archive,Reason,SharedArchives;public byte[] Main,Raw,Flags;public int Width,Height,Format;public ulong Patch;
 }
 sealed class LooseFile : IDisposable {
  public string Path;public long Length,Ticks;FileStream stream;
  public LooseFile(string path){Path=path;var info=new FileInfo(path);Length=info.Length;Ticks=info.LastWriteTimeUtc.Ticks;stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);}
  public void Bounds(ulong at,uint size){if(at>(ulong)Length||(ulong)size>(ulong)Length-at)throw new Exception("Loose LUT source bounds: "+System.IO.Path.GetFileName(Path));}
  public byte[] Read(ulong at,int size){if(size<0||size>128*1024*1024)throw new Exception("Loose LUT read budget");Bounds(at,(uint)size);stream.Position=(long)at;var result=new byte[size];int written=0;while(written<size){Check();int got=stream.Read(result,written,Math.Min(65536,size-written));if(got==0)throw new Exception("Short loose LUT read");written+=got;}return result;}
  public void Verify(){var info=new FileInfo(Path);if(!info.Exists||info.Length!=Length||info.LastWriteTimeUtc.Ticks!=Ticks)throw new Exception("Loose LUT source changed while reading: "+System.IO.Path.GetFileName(Path));}
  public void Dispose(){stream.Dispose();}
 }
 static string[] PatchNames(string folder){var names=new List<string>();foreach(string path in Directory.GetFiles(folder,"*",SearchOption.TopDirectoryOnly)){string name=Path.GetFileName(path);if(Regex.IsMatch(name,"^[0-9a-fA-F]{16}\\.patch_[0-9]+$"))names.Add(name);}if(names.Count>4096)throw new Exception("Loose LUT patch count budget");names.Sort(StringComparer.Ordinal);return names.ToArray();}
 static bool Equal(byte[] left,byte[] right){if(left==null||right==null)return left==right;if(left.Length!=right.Length)return false;for(int i=0;i<left.Length;i++)if(left[i]!=right[i])return false;return true;}
 static Lut Metadata(string hash,string archive,byte[] main){
  var result=new Lut{Hash=hash,Archive=archive,Main=main};
  if(main==null||main.Length!=340||Encoding.ASCII.GetString(main,192,4)!="DDS "||Encoding.ASCII.GetString(main,276,4)!="DX10"){result.Reason="DDS metadata unavailable";return result;}
  if(U(main,196)!=124||U(main,268)!=32){result.Reason="Invalid DDS header";return result;}
  int width=N(U(main,208)),height=N(U(main,204)),format=N(U(main,320)),layers=N(U(main,332)),mips=Math.Max(1,N(U(main,220)));
  if((width!=23&&(width!=3||height!=1))||height<1||height>64||(format!=2&&format!=10)||layers!=1||mips>32||U(main,324)!=3||U(main,328)!=0){result.Reason="Unsupported LUT dimensions or format";return result;}
  result.Width=width;result.Height=height;result.Format=format;return result;
 }
 static int PixelBytes(Lut value){int total=0,per=value.Format==2?16:8,mips=Math.Max(1,N(U(value.Main,220)));for(int mip=0;mip<mips;mip++)total=checked(total+Math.Max(1,value.Width>>mip)*Math.Max(1,value.Height>>mip)*per);return total;}
 static void Finite(Lut value){int per=value.Format==2?4:2;for(int at=0;at<value.Raw.Length;at+=per){float number=value.Format==2?BitConverter.ToSingle(value.Raw,at):(float)Half(BitConverter.ToUInt16(value.Raw,at));if(float.IsNaN(number)||float.IsInfinity(number))throw new Exception("Nonfinite LUT "+value.Hash);}}
 // Only metadata and the small LUT pixel spans are read. Large model/texture
 // sidecars remain untouched; lexical ordering is for hashing only. Within one
 // archive family, the game applies numeric patch layers from low to high.
 sealed class LooseSet : IDisposable {
  public Dictionary<string,List<Lut>> Values=new Dictionary<string,List<Lut>>(StringComparer.Ordinal);
  Dictionary<string,LooseFile> files=new Dictionary<string,LooseFile>(StringComparer.OrdinalIgnoreCase);string folder;string[] names;bool bundledOnly;long metadataBytes,retainedBytes,rowCount;
  public LooseSet(string path,HashAlgorithm digest,bool arrowhead=false){folder=path;bundledOnly=arrowhead;names=arrowhead?new string[0]:PatchNames(path);try{foreach(string name in names){Check();var file=Open(name);var head=file.Read(0,72);if(U(head,0)!=0xf0000011)throw new Exception("Invalid loose LUT patch header: "+name);int types=N(U(head,4)),count=N(U(head,8));if(types>4096||count>100000)throw new Exception("Loose LUT TOC budget");int start=checked(72+types*32),tocBytes=checked(start+count*80);metadataBytes=checked(metadataBytes+tocBytes);rowCount=checked(rowCount+count);if(metadataBytes>LooseBudget||rowCount>LooseRowBudget)throw new Exception("Loose LUT metadata budget exceeded");var toc=file.Read(0,tocBytes);Hash(digest,Encoding.ASCII.GetBytes(name+"\n"));Hash(digest,toc);for(int i=0;i<count;i++){int p=start+i*80;if(Q(toc,p+8)!=TextureType)continue;string hash=Q(toc,p).ToString("x16");file.Bounds(Q(toc,p+16),U(toc,p+56));retainedBytes=checked(retainedBytes+340+80);if(retainedBytes>LooseBudget)throw new Exception("Loose LUT retained byte budget exceeded");byte[] main=U(toc,p+56)>=340?file.Read(Q(toc,p+16),340):null;var value=Metadata(hash,name.Substring(0,16).ToLowerInvariant(),main);value.Patch=UInt64.Parse(name.Substring(name.LastIndexOf('_')+1),System.Globalization.CultureInfo.InvariantCulture);value.Flags=Slice(toc,p+56,20);Hash(digest,Encoding.ASCII.GetBytes(hash+"\n"));if(main!=null)Hash(digest,main);if(value.Reason==null){uint gpu=U(toc,p+64),stream=U(toc,p+60);LooseFile gf=gpu==0?null:Open(name+".gpu_resources"),sf=stream==0?null:Open(name+".stream");if(gf!=null)gf.Bounds(Q(toc,p+32),gpu);if(sf!=null)sf.Bounds(Q(toc,p+24),stream);int total=PixelBytes(value);retainedBytes=checked(retainedBytes+total);if(retainedBytes>LooseBudget)throw new Exception("Loose LUT retained byte budget exceeded");if(gpu>=total)value.Raw=gf.Read(Q(toc,p+32),total);else if(stream>=total)value.Raw=sf.Read(Q(toc,p+24),total);else if((ulong)gpu+stream>=(ulong)total){int take=(int)Math.Min(stream,(uint)total);value.Raw=new byte[total];if(take>0)Buffer.BlockCopy(sf.Read(Q(toc,p+24),take),0,value.Raw,0,take);if(take<total)Buffer.BlockCopy(gf.Read(Q(toc,p+32),total-take),0,value.Raw,take,total-take);}else throw new Exception("Short loose LUT data "+hash);Finite(value);Hash(digest,value.Raw);}List<Lut> rows;if(!Values.TryGetValue(hash,out rows)){rows=new List<Lut>();Values.Add(hash,rows);}rows.Add(value);}}Verify();}catch{Dispose();throw;}}
  LooseFile Open(string name){LooseFile value;if(!files.TryGetValue(name,out value)){string path=Path.Combine(folder,name);if(!File.Exists(path))throw new Exception("Loose LUT sidecar missing: "+name);value=new LooseFile(path);files.Add(name,value);}return value;}
  public Lut Resolve(string hash){
   List<Lut> rows;if(!Values.TryGetValue(hash,out rows))return null;
   var families=new SortedDictionary<string,Lut>(StringComparer.Ordinal);
   foreach(var value in rows){Lut top;if(!families.TryGetValue(value.Archive,out top)||value.Patch>top.Patch)families[value.Archive]=value;}
   Lut first=null;var labels=new List<string>();
   foreach(var pair in families){var top=pair.Value;labels.Add(top.Archive+".patch_"+top.Patch);
    if(top.Reason!=null)throw new Exception("Loose replacement for LUT "+hash+" in "+labels[labels.Count-1]+": "+top.Reason);
    foreach(var value in rows)if(value.Archive==top.Archive&&value.Patch==top.Patch&&(value.Reason!=null||!Equal(value.Main,top.Main)||!Equal(value.Raw,top.Raw)||!Equal(value.Flags,top.Flags)))throw new Exception("Ambiguous loose LUT replacements for "+hash+" at patch_"+top.Patch+"; exact source proof required");
    if(first==null)first=top;
   }
   foreach(var top in families.Values)if(!Equal(top.Main,first.Main)||!Equal(top.Raw,first.Raw)||!Equal(top.Flags,first.Flags))throw new Exception("Ambiguous loose LUT replacements for "+hash+" across archive families ("+String.Join(", ",labels.ToArray())+"); palettes differ; exact source proof required");
   // Equal bytes prove colors, not which archive supplied the live binding.
   // Keep that distinction: load pixels but omit single-archive export proof.
   if(families.Count>1)first.SharedArchives=String.Join("\n",labels.ToArray())+"\n";
   return first;
  }
  public void Verify(){if(bundledOnly)return;foreach(var file in files.Values)file.Verify();string[] current=PatchNames(folder);if(current.Length!=names.Length)throw new Exception("Loose LUT patch set changed while reading");for(int i=0;i<names.Length;i++)if(current[i]!=names[i])throw new Exception("Loose LUT patch set changed while reading");}
  public void Dispose(){foreach(var file in files.Values)file.Dispose();files.Clear();}
 }
 static void Hash(HashAlgorithm sha,byte[] value){if(sha!=null&&value.Length>0)sha.TransformBlock(value,0,value.Length,value,0);}
 static string FileDigest(string path){using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))using(var sha=SHA256.Create()){var buffer=new byte[65536];int got;while((got=file.Read(buffer,0,buffer.Length))>0){Check();Hash(sha,Slice(buffer,0,got));}sha.TransformFinalBlock(buffer,0,0);return BitConverter.ToString(sha.Hash).Replace("-","");}}
 static string Stamp(string folder){string bundled=FileDigest(Path.Combine(folder,"bundles.nxa"));if(PatchNames(folder).Length==0)return bundled;using(var sha=SHA256.Create()){Hash(sha,Encoding.ASCII.GetBytes("Epic LUT patched originals v6\n"+bundled+"\n"));using(var loose=new LooseSet(folder,sha)){}sha.TransformFinalBlock(new byte[0],0,0);return BitConverter.ToString(sha.Hash).Replace("-","");}}
 public static string SourceStamp(string folder,int ownerPID,string status){owner=ownerPID;progress=status;healthChecked=false;return Stamp(folder);}
 static void WriteLut(string destination,Lut value){int size=checked(value.Width*value.Height*16);var pixels=new byte[size];for(int f=0;f<size/4;f++){float number=value.Format==2?BitConverter.ToSingle(value.Raw,f*4):(float)Half(BitConverter.ToUInt16(value.Raw,f*2));Buffer.BlockCopy(BitConverter.GetBytes(number),0,pixels,f*4,4);}var header=Slice(value.Main,192,148);Buffer.BlockCopy(BitConverter.GetBytes((uint)1),0,header,28,4);Buffer.BlockCopy(BitConverter.GetBytes((uint)2),0,header,128,4);Buffer.BlockCopy(BitConverter.GetBytes((uint)(value.Width*16)),0,header,20,4);string file=Path.Combine(destination,"game-"+value.Hash+"-original.dds");Write(file,header,pixels);string patch=Path.Combine(destination,"game-"+value.Hash+"-original.patch-source");if(value.SharedArchives==null)Write(patch,Encoding.ASCII.GetBytes(value.Archive+"\n"),value.Main);else {if(File.Exists(patch))File.Delete(patch);Write(Path.Combine(destination,"game-"+value.Hash+"-original.source-archives"),Encoding.ASCII.GetBytes(value.SharedArchives),new byte[0]);}}
 // Serialize atomic cache publication across background worker processes.
 // The lock is bounded and never runs on the game's update thread.
 static void Publish(string temporary,string path){
  string key;using(var hash=SHA256.Create())key=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant()))).Replace("-","");
  using(var mutex=new System.Threading.Mutex(false,"Local\\EpicLUTSnapshot-"+key)){
   bool held=false;
   try{try{held=mutex.WaitOne(5000);}catch(System.Threading.AbandonedMutexException){held=true;}
    if(!held)throw new IOException("Snapshot cache publication timed out; retry Load Current Gear");
    if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
   }finally{if(held)mutex.ReleaseMutex();}
  }
 }
 static void Write(string path,byte[] head,byte[] data){string temporary=path+"."+Guid.NewGuid().ToString("N")+".pending";try{using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){output.Write(head,0,head.Length);output.Write(data,0,data.Length);output.Flush(true);}Publish(temporary,path);}finally{if(File.Exists(temporary))File.Delete(temporary);}}
 public int Extract(string destination,string wantedPath){return ExtractChecked(destination,wantedPath,null);}
 int ExtractChecked(string destination,string wantedPath,string expected,bool arrowhead=false){
  string before=expected??Stamp(folder);
  HashSet<string> wanted=String.IsNullOrEmpty(wantedPath)?null:new HashSet<string>(File.ReadAllLines(wantedPath),StringComparer.Ordinal);
  if(wanted!=null){if(wanted.Count<1||wanted.Count>16384)throw new Exception("Equipped LUT request count");foreach(string value in wanted)if(!Regex.IsMatch(value,"^[0-9a-f]{16}$"))throw new Exception("Invalid equipped LUT request");}
  var selected=new Dictionary<string,Lut>(StringComparer.Ordinal);int visited=0,archiveCount=0;
  using(var loose=new LooseSet(folder,null,arrowhead)){
   // Requested replacements resolve first, including invalid metadata. A broken
   // override must never silently recolor the custom model with stock pixels.
   if(wanted!=null){foreach(string hash in wanted)if(loose.Values.ContainsKey(hash))selected.Add(hash,loose.Resolve(hash));}
   else foreach(var pair in loose.Values){Lut candidate=null;foreach(var value in pair.Value)if(value.Reason==null){candidate=value;break;}if(candidate!=null)selected.Add(pair.Key,candidate);}
   foreach(var pair in entries){ulong id;if(pair.Key.Length==16&&ulong.TryParse(pair.Key,System.Globalization.NumberStyles.HexNumber,null,out id))archiveCount++;}
   foreach(var pair in entries){if(wanted!=null&&selected.Count>=wanted.Count)break;string name=pair.Key;if(name.Length!=16)continue;ulong archiveHash;if(!ulong.TryParse(name,System.Globalization.NumberStyles.HexNumber,null,out archiveHash))continue;
    Pulse(wanted==null?"Indexing game resources: "+(100*(++visited)/Math.Max(1,archiveCount))+"%":"Reading equipped original LUTs: "+(100*selected.Count/Math.Max(1,wanted.Count))+"% ("+selected.Count+"/"+wanted.Count+" tables)");
    var head=Read(name,0,72);if(U(head,0)!=0xf0000011)continue;int types=N(U(head,4)),count=N(U(head,8));if(types>4096||count>100000)throw new Exception("TOC count");int start=checked(72+types*32);var toc=Read(name,0,checked(start+count*80));
    for(int i=0;i<count;i++){Check();int p=start+i*80;if(Q(toc,p+8)!=TextureType||U(toc,p+56)<340)continue;string hash=Q(toc,p).ToString("x16");if(selected.ContainsKey(hash)||(wanted!=null&&!wanted.Contains(hash)))continue;var value=Metadata(hash,name.ToLowerInvariant(),Read(name,Q(toc,p+16),340));if(value.Reason!=null)continue;
     if(loose.Values.ContainsKey(hash)){selected.Add(hash,wanted==null?value:loose.Resolve(hash));continue;}
     if(wanted!=null){int total=PixelBytes(value);uint gpu=U(toc,p+64),stream=U(toc,p+60);if(gpu>=total)value.Raw=Read(name+".gpu_resources",Q(toc,p+32),total);else if(stream>=total)value.Raw=Read(name+".stream",Q(toc,p+24),total);else if((ulong)gpu+stream>=(ulong)total){int take=(int)Math.Min(stream,(uint)total);value.Raw=new byte[total];if(take>0)Buffer.BlockCopy(Read(name+".stream",Q(toc,p+24),take),0,value.Raw,0,take);if(take<total)Buffer.BlockCopy(Read(name+".gpu_resources",Q(toc,p+32),total-take),0,value.Raw,take,total-take);}else throw new Exception("Short LUT data "+hash);Finite(value);}
     selected.Add(hash,value);if(selected.Count>16384)throw new Exception("Original LUT budget");
    }
   }
   loose.Verify();
  }
  // Verify all relevant content, not only timestamps, before publishing output.
  if(before!=Stamp(folder))throw new Exception("Original LUT sources changed during capture; retry");
  Directory.CreateDirectory(destination);
  if(wanted==null){var catalog=new List<string>(selected.Keys);catalog.Sort(StringComparer.Ordinal);Write(Path.Combine(destination,"catalog.txt"),Encoding.ASCII.GetBytes(String.Join("\n",catalog.ToArray())+"\n"),new byte[0]);}
  else foreach(var value in selected.Values)WriteLut(destination,value);
  return selected.Count;
 }
 public static int RunArrowhead(string folder,string destination,int ownerPID,string status,string wanted,string expected){owner=ownerPID;progress=status;healthChecked=false;using(var reader=new EpicOriginalReader(folder))return reader.ExtractChecked(destination,wanted,expected,true);}
 public static int RunChecked(string folder,string destination,int ownerPID,string status,string wanted,string expected){owner=ownerPID;progress=status;healthChecked=false;using(var reader=new EpicOriginalReader(folder))return reader.ExtractChecked(destination,wanted,expected);}
 public void Dispose(){index.Dispose();foreach(var b in bundles.Values)b.Dispose();}
 public static int Run(string folder,string destination,int ownerPID,string status,string wanted){owner=ownerPID;progress=status;using(var r=new EpicOriginalReader(folder))return r.Extract(destination,wanted);}
}
