// Bounded, read-only unit/material provenance. Archive format research:
// CowboyBingus (vendor/LICENSE), HD2SDK CE 5a886256. No game-native calls.
using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

public static class EpicBindingProvenanceReader {
 const ulong UnitType=0xe0a48d0be9a7453fUL, MaterialType=0xeac0b497876adedfUL, TextureType=0xcd4238c6a0c69e32UL;
 const int FileBudget=8*1024*1024, SetBudget=256*1024*1024, RequestBudget=4096;
 const long MetadataBudget=512L*1024*1024, RowBudget=6000000;
 static readonly BindingFlags Hidden=BindingFlags.Instance|BindingFlags.NonPublic;
 static long lastHealthCheck;static bool checkedHealth;
 sealed class Request {public ulong Unit;public string Preferred;}
 sealed class Archive {public string Name,Hash;public int Size,Start,Count;public bool Materials;}
 sealed class LooseFile {public string Path;public long Length,Ticks;}
 sealed class LooseCandidate {public string Archive;public LooseFile Main,GPU,Stream;public byte[] TOC;public int At;}
 sealed class Resource {
  public ulong Name,Type;public string Archive,SourceFile;
  public byte[] Main,GPU,Stream,TOC;
  public long Bytes {get{return (long)Main.Length+GPU.Length+Stream.Length+TOC.Length;}}
 }
 static uint U(byte[] bytes,int at) {
  if(at<0 || at>bytes.Length-4)throw new Exception("Binding provenance integer bounds");
  return BitConverter.ToUInt32(bytes,at);
 }
 static ulong Q(byte[] bytes,int at) {
  if(at<0 || at>bytes.Length-8)throw new Exception("Binding provenance offset bounds");
  return BitConverter.ToUInt64(bytes,at);
 }
 static string Hex(ulong value){return value.ToString("x16",CultureInfo.InvariantCulture);}
 static string Digest(byte[] bytes) {
  using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
 }
 static string DigestFile(string path,string status,Stopwatch clock,int owner) {
  using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
  using(var sha=SHA256.Create()) {
   byte[] buffer=new byte[65536];int got;
   while((got=stream.Read(buffer,0,buffer.Length))>0){Check(status,clock,owner);sha.TransformBlock(buffer,0,got,buffer,0);}
   sha.TransformFinalBlock(buffer,0,0);
   return BitConverter.ToString(sha.Hash).Replace("-","").ToLowerInvariant();
  }
 }
 static bool Equal(byte[] a,byte[] b) {
  if(a.Length!=b.Length)return false;
  for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;
  return true;
 }
 static void Check(string status,Stopwatch clock,int ownerPID) {
  if(clock.Elapsed.TotalSeconds>180)throw new Exception("Binding provenance lookup exceeded 180 seconds");
  if(checkedHealth && clock.ElapsedMilliseconds-lastHealthCheck<100)return;
  checkedHealth=true;lastHealthCheck=clock.ElapsedMilliseconds;
  if(File.Exists(status+".cancel"))throw new Exception("Binding provenance extraction canceled");
  if(ownerPID!=0) {
   string heartbeat=Path.Combine(Path.GetDirectoryName(status),"owner-heartbeat.txt");
   if(!File.Exists(heartbeat) || (DateTime.UtcNow-File.GetLastWriteTimeUtc(heartbeat)).TotalSeconds>15)
    throw new Exception("Binding provenance game heartbeat expired");
   int recorded;
   try {
    if(!int.TryParse(File.ReadAllText(heartbeat).Trim(),out recorded) || recorded!=ownerPID)
     throw new Exception("Binding provenance game owner changed");
   } catch(IOException) {throw new Exception("Binding provenance game heartbeat unavailable");}
  }
 }
 static byte[] Read(EpicOriginalReader reader,MethodInfo method,string archive,ulong at,int size,string status,Stopwatch clock,int owner) {
  Check(status,clock,owner);byte[] bytes;
  try{bytes=(byte[])method.Invoke(reader,new object[]{archive,at,size});}
  catch(TargetInvocationException error){throw error.InnerException ?? error;}
  Check(status,clock,owner);
  if(bytes==null || bytes.Length!=size)throw new Exception("Short binding provenance resource");
  return bytes;
 }
 static string Child(string output,string filename) {
  if(filename!=Path.GetFileName(filename) || filename.IndexOfAny(new char[]{'/', '\\', ':'})>=0)
   throw new Exception("Binding provenance cache filename leaves version folder");
  string path=Path.GetFullPath(Path.Combine(output,filename));
  if(!path.StartsWith(output.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))
   throw new Exception("Binding provenance cache path leaves version folder");
  return path;
 }
 static void Atomic(string path,Action<FileStream> write) {
  // The entry script validates existing paths (including each cache child)
  // against junctions/symlinks while preserving OneDrive cloud placeholders.
  string temporary=path+"."+Guid.NewGuid().ToString("N")+".pending";
  try {
   using(var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){write(stream);stream.Flush(true);}
   if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
  } finally {if(File.Exists(temporary))File.Delete(temporary);}
 }
 static void AtomicBytes(string path,byte[] bytes){Atomic(path,delegate(FileStream stream){stream.Write(bytes,0,bytes.Length);});}
 static List<Request> Requests(string path) {
  var info=new FileInfo(path);
  if(!info.Exists || info.Length<1 || info.Length>RequestBudget)throw new Exception("Binding provenance request byte bounds");
  string text=new UTF8Encoding(false,true).GetString(File.ReadAllBytes(path));
  text=text.Replace("\r\n","\n");
  if(text.EndsWith("\n",StringComparison.Ordinal))text=text.Substring(0,text.Length-1);
  string[] lines=text.Split('\n');
  if(lines.Length<1 || lines.Length>64)throw new Exception("Binding provenance request unit bounds");
  var result=new List<Request>();var seen=new HashSet<ulong>();
  foreach(string line in lines) {
   ulong unit,archive;
   if(line.Length!=33 || line[16]!='\t' || !ulong.TryParse(line.Substring(0,16),NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out unit)
      || !ulong.TryParse(line.Substring(17,16),NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out archive))
    throw new Exception("Binding provenance request must contain dense unit/archive hex pairs");
   if(!seen.Add(unit))throw new Exception("Duplicate binding provenance request unit");
   result.Add(new Request{Unit=unit,Preferred=Hex(archive)});
  }
  return result;
 }
 static long IndexBudget(string folder) {
  // The reviewed reader materializes the DSAA index. Reject oversized logical
  // indices before its constructor can allocate them.
  using(var stream=new FileStream(Path.Combine(folder,"bundles.nxa"),FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
   var header=new byte[32];if(stream.Read(header,0,32)!=32 || Encoding.ASCII.GetString(header,0,4)!="DSAR")
    throw new Exception("Binding provenance index DSAR header unavailable");
   uint count=U(header,8);
   if(count<1 || count>1000000 || 32L+count*32L>stream.Length)throw new Exception("Binding provenance index chunk bounds");
   stream.Position=32L+(count-1)*32L;
   var last=new byte[32];if(stream.Read(last,0,32)!=32)throw new Exception("Short binding provenance index chunk");
   ulong logical=checked(Q(last,0)+U(last,16));
   if(logical<24 || logical>(ulong)MetadataBudget || logical+32UL+count*32UL>(ulong)MetadataBudget)
    throw new Exception("Binding provenance index metadata budget exceeded");
   return checked((long)logical+32L+count*32L);
  }
 }
 static List<string> Order(List<string> names,IEnumerable<string> preferred) {
  var result=new List<string>();var seen=new HashSet<string>(StringComparer.Ordinal);
  foreach(string name in preferred)if(names.Contains(name) && seen.Add(name))result.Add(name);
  foreach(string name in new string[]{"18235e0c9ec0e636","ee6b1ba7e22d71ed"})
   if(names.Contains(name) && seen.Add(name))result.Add(name);
  foreach(string name in names)if(seen.Add(name))result.Add(name);
  return result;
 }
 static Resource Load(EpicOriginalReader reader,MethodInfo method,string archive,byte[] toc,int at,string status,Stopwatch clock,int owner,long retained) {
  uint main=U(toc,at+56),stream=U(toc,at+60),gpu=U(toc,at+64);
  if(main<1 || main>FileBudget || stream>FileBudget || gpu>FileBudget)
   throw new Exception("Binding provenance resource file byte budget exceeded");
  if(retained+(long)main+stream+gpu+80>SetBudget)throw new Exception("Binding provenance resource set byte budget exceeded");
  var record=new byte[80];Buffer.BlockCopy(toc,at,record,0,80);
  return new Resource{Name=Q(toc,at),Type=Q(toc,at+8),Archive=archive,TOC=record,
   Main=Read(reader,method,archive,Q(toc,at+16),(int)main,status,clock,owner),
   Stream=stream==0?new byte[0]:Read(reader,method,archive+".stream",Q(toc,at+24),(int)stream,status,clock,owner),
   GPU=gpu==0?new byte[0]:Read(reader,method,archive+".gpu_resources",Q(toc,at+32),(int)gpu,status,clock,owner)};
 }
 static void Remember(Dictionary<ulong,Resource> set,Resource value,ref long total) {
  Resource old;
  if(set.TryGetValue(value.Name,out old)) {
   if(!Equal(old.Main,value.Main) || !Equal(old.GPU,value.GPU) || !Equal(old.Stream,value.Stream))
    throw new Exception("Conflicting duplicate binding provenance resource bytes: "+Hex(value.Name)+"."+Hex(value.Type));
   // Offsets, row index, and qwords40/48 are archive-specific: the observed
   // shared/owning material copies have identical payloads and flags but
   // different qwords. Preserve the preferred archive's exact original TOC;
   // never normalize those fields. Lengths and native flags must still agree.
   for(int i=56;i<76;i++)if(old.TOC[i]!=value.TOC[i])
    throw new Exception("Conflicting duplicate binding provenance TOC metadata: "+Hex(value.Name));
   return;
  }
  set.Add(value.Name,value);total+=value.Bytes;
 }
 static HashSet<ulong> UnitMaterials(Resource unit) {
  if(unit.Main.Length<116)throw new Exception("Truncated binding provenance unit header");
  uint at=U(unit.Main,112);
  if(at<116 || at>(uint)(unit.Main.Length-4))throw new Exception("Binding provenance unit material table offset bounds");
  uint count=U(unit.Main,(int)at);
  if(count<1 || count>64 || at+4L+count*12L>unit.Main.Length)throw new Exception("Binding provenance unit material table count bounds");
  var result=new HashSet<ulong>();var sections=new Dictionary<uint,ulong>();
  for(int i=0;i<count;i++) {
   uint section=U(unit.Main,checked((int)at+4+i*4));
   ulong material=Q(unit.Main,checked((int)at+4+(int)count*4+i*8)),old;
   if(sections.TryGetValue(section,out old) && old!=material)throw new Exception("Ambiguous binding provenance unit SectionID");
   sections[section]=material;result.Add(material);
  }
  return result;
 }
 static LooseFile Loose(string path,bool optional) {
  if(!File.Exists(path)) {
   if(optional)return null;
   throw new Exception("Binding provenance loose patch part missing: "+Path.GetFileName(path));
  }
  if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)
   throw new Exception("Binding provenance loose patch path is redirected");
  var info=new FileInfo(path);
  return new LooseFile{Path=path,Length=info.Length,Ticks=info.LastWriteTimeUtc.Ticks};
 }
 static void LooseBounds(LooseFile file,ulong at,uint size,string part) {
  if(size==0)return;
  if(file==null)throw new Exception("Binding provenance loose patch part missing: "+part);
  if(at>(ulong)file.Length || (ulong)size>(ulong)file.Length-at)
   throw new Exception("Binding provenance loose patch part bounds: "+part);
 }
 static byte[] LooseRead(LooseFile file,ulong at,int size,string status,Stopwatch clock,int owner) {
  if(size<0 || size>72+4096*32+100000*80)throw new Exception("Binding provenance loose patch read byte bounds");
  LooseBounds(file,at,(uint)size,Path.GetFileName(file.Path));Check(status,clock,owner);
  var bytes=new byte[size];
  using(var stream=new FileStream(file.Path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {
   stream.Position=(long)at;int read=0;
   while(read<size) {
    Check(status,clock,owner);int got=stream.Read(bytes,read,Math.Min(65536,size-read));
    if(got==0)throw new Exception("Short binding provenance loose patch read");read+=got;
   }
  }
  return bytes;
 }
 static Resource LooseResource(string archive,LooseFile main,LooseFile gpu,LooseFile stream,byte[] toc,int at,string status,Stopwatch clock,int owner,long retained) {
  uint mainSize=U(toc,at+56),streamSize=U(toc,at+60),gpuSize=U(toc,at+64);
  if(mainSize<1 || mainSize>FileBudget || streamSize>FileBudget || gpuSize>FileBudget)
   throw new Exception("Binding provenance loose patch resource file byte budget exceeded");
  if(retained+(long)mainSize+streamSize+gpuSize+80>SetBudget)
   throw new Exception("Binding provenance loose patch resource set byte budget exceeded");
  var record=new byte[80];Buffer.BlockCopy(toc,at,record,0,80);
  return new Resource{Name=Q(toc,at),Type=Q(toc,at+8),Archive=archive,TOC=record,
   Main=LooseRead(main,Q(toc,at+16),(int)mainSize,status,clock,owner),
   GPU=gpuSize==0?new byte[0]:LooseRead(gpu,Q(toc,at+32),(int)gpuSize,status,clock,owner),
   Stream=streamSize==0?new byte[0]:LooseRead(stream,Q(toc,at+24),(int)streamSize,status,clock,owner)};
 }
 static void Unchanged(LooseFile file) {
  if(file==null)return;
  var current=Loose(file.Path,false);
  if(current.Length!=file.Length || current.Ticks!=file.Ticks)
   throw new Exception("Binding provenance loose patch changed during extraction");
 }
 static void Effective(Dictionary<ulong,Resource> selected,Dictionary<ulong,Resource> loose,Resource candidate,ref long total) {
  Resource previous;
  if(loose.TryGetValue(candidate.Name,out previous)) {
   // No numeric patch-priority guess: distinct loose replacements refuse.
   try {long ignored=0;Remember(loose,candidate,ref ignored);}
   catch(Exception error){throw new Exception("Ambiguous effective weapon binding overrides: "+Hex(candidate.Name)+"; "+error.Message);}
   return;
  }
  long retained=selected.TryGetValue(candidate.Name,out previous)?total-previous.Bytes:total;
  if(retained+candidate.Bytes>SetBudget)throw new Exception("Effective weapon binding source set byte budget exceeded");
  candidate.SourceFile=candidate.Archive;
  candidate.Archive=candidate.Archive.Substring(0,16).ToLowerInvariant();
  loose.Add(candidate.Name,candidate);selected[candidate.Name]=candidate;total=retained+candidate.Bytes;
 }
 static string ScanLoose(string game,Dictionary<ulong,Resource> units,Dictionary<ulong,Resource> materials,
                         Dictionary<ulong,HashSet<ulong>> collisions,ref long metadata,ref long rows,long total,
                         string status,Stopwatch clock,int owner,bool effective,Dictionary<ulong,List<LooseCandidate>> looseMaterials,
                         out List<LooseFile> observedFiles,out long effectiveTotal) {
  var paths=new List<string>();
  foreach(string path in Directory.EnumerateFiles(game)) {
   string name=Path.GetFileName(path);
   var companion=Regex.Match(name,@"^([0-9a-fA-F]{16}\.patch_[0-9]+)\.(gpu_resources|stream)$",RegexOptions.CultureInvariant);
   if(companion.Success && !File.Exists(Path.Combine(game,companion.Groups[1].Value)))
    throw new Exception("Binding provenance loose patch main missing for companion: "+name);
   if(!Regex.IsMatch(name,@"^[0-9a-fA-F]{16}\.patch_[0-9]+$",RegexOptions.CultureInvariant))continue;
   paths.Add(path);metadata+=name.Length*2L+128;
   if(paths.Count>4096)throw new Exception("Binding provenance loose patch count exceeds its limit");
   if(metadata>MetadataBudget)throw new Exception("Binding provenance loose patch metadata budget exceeded");
  }
  paths.Sort(StringComparer.Ordinal);var scope=new StringBuilder();var observed=new List<LooseFile>();
  var looseUnits=new Dictionary<ulong,Resource>();
  foreach(string path in paths) {
   Check(status,clock,owner);string archive=Path.GetFileName(path);
   File.WriteAllText(status,"Checking loose binding patch sources: "+archive);
   var main=Loose(path,false);var gpu=Loose(path+".gpu_resources",true);var stream=Loose(path+".stream",true);
   if(main.Length<72)throw new Exception("Binding provenance loose patch TOC header bounds");
   byte[] header=LooseRead(main,0,72,status,clock,owner);
   if(U(header,0)!=0xf0000011)throw new Exception("Binding provenance loose patch TOC header invalid");
   uint types=U(header,4),count=U(header,8);
   if(types>4096 || count>100000)throw new Exception("Binding provenance loose patch TOC count bounds");
   int start=checked(72+(int)types*32),size=checked(start+(int)count*80);
   metadata+=72L+size;rows+=count;
   if(metadata>MetadataBudget || rows>RowBudget)throw new Exception("Binding provenance loose patch TOC metadata budget exceeded");
   byte[] toc=LooseRead(main,0,size,status,clock,owner);
   for(int i=0;i<count;i++) {
    Check(status,clock,owner);int at=start+i*80;ulong resource=Q(toc,at),type=Q(toc,at+8);
    // Even unrelated Lua/texture rows must have complete, bounded triplets.
    LooseBounds(main,Q(toc,at+16),U(toc,at+56),archive);
    LooseBounds(stream,Q(toc,at+24),U(toc,at+60),archive+".stream");
    LooseBounds(gpu,Q(toc,at+32),U(toc,at+64),archive+".gpu_resources");
    HashSet<ulong> collision;
    if(collisions.TryGetValue(type,out collision) && collision.Add(resource)) {
     metadata+=24;if(metadata>MetadataBudget)throw new Exception("Binding provenance loose patch collision metadata budget exceeded");
    }
    if(effective && type==MaterialType) {
     List<LooseCandidate> candidates;
     if(!looseMaterials.TryGetValue(resource,out candidates)){candidates=new List<LooseCandidate>();looseMaterials.Add(resource,candidates);}
     candidates.Add(new LooseCandidate{Archive=archive,Main=main,GPU=gpu,Stream=stream,TOC=toc,At=at});
     metadata+=64;if(metadata>MetadataBudget)throw new Exception("Effective weapon material locator budget exceeded");
    }
    var set=type==UnitType?units:type==MaterialType?materials:null;Resource original;
    if(set==null || !set.TryGetValue(resource,out original))continue;
    Resource candidate=LooseResource(archive,main,gpu,stream,toc,at,status,clock,owner,total-original.Bytes);
    if(effective) {
     if(type==UnitType)Effective(units,looseUnits,candidate,ref total);
     continue;
    }
    try {long retained=total;Remember(set,candidate,ref retained);}
    catch(Exception error){throw new Exception("Loose patch overrides requested binding source: "+archive+" / "+Hex(resource)+"; "+error.Message);}
   }
   // Hash complete loose triplets using fixed-size reads. The fingerprint
   // includes unrelated patch bodies; no archive payload is retained for it.
   scope.Append(archive).Append('\t');
   foreach(var file in new LooseFile[]{main,gpu,stream}) {
    if(file==null){scope.Append("-\t-\t");continue;}
    scope.Append(file.Length.ToString(CultureInfo.InvariantCulture)).Append('\t')
     .Append(DigestFile(file.Path,status,clock,owner)).Append('\t');
    Unchanged(file);observed.Add(file);
   }
   scope.Append('\n');
  }
  foreach(var file in observed)Unchanged(file);
  observedFiles=observed;effectiveTotal=total;
  return "top-level-game-data-patches-v1\n"+paths.Count.ToString(CultureInfo.InvariantCulture)+"\n"
   +Digest(new UTF8Encoding(false).GetBytes(scope.ToString()))+"\n";
 }
 public static int Run(string gameData,string destination,string requestPath,int ownerPID,string status) {
  return Run(gameData,destination,requestPath,ownerPID,status,"stock");
 }
 public static int Run(string gameData,string destination,string requestPath,int ownerPID,string status,string mode) {
  if(mode!="stock" && mode!="weapon_effective")throw new Exception("Unsupported binding provenance mode");
  bool effective=mode=="weapon_effective";
  string game=Path.GetFullPath(gameData).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
  string output=Path.GetFullPath(destination),request=Path.GetFullPath(requestPath);
  if((output+Path.DirectorySeparatorChar).StartsWith(game,StringComparison.OrdinalIgnoreCase)
     || request.StartsWith(game,StringComparison.OrdinalIgnoreCase))throw new Exception("Binding provenance cache/request cannot be inside game data");
  if(!Directory.Exists(game) || !Directory.Exists(output) || ownerPID<0)throw new Exception("Binding provenance directories/owner unavailable");
  string statusPath=Path.GetFullPath(status),cache=Path.GetDirectoryName(statusPath).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
  if(Path.GetFileName(statusPath)!="progress.txt" || !output.StartsWith(cache,StringComparison.OrdinalIgnoreCase)
     || cache.StartsWith(game,StringComparison.OrdinalIgnoreCase))throw new Exception("Binding provenance status/cache path differs");
  var requests=Requests(request);var clock=Stopwatch.StartNew();checkedHealth=false;Check(status,clock,ownerPID);
  long metadata=IndexBudget(game),rows=0,total=0;int visited=0;
  var flags=BindingFlags.Static|BindingFlags.NonPublic;
  typeof(EpicOriginalReader).GetField("owner",flags).SetValue(null,ownerPID);
  typeof(EpicOriginalReader).GetField("progress",flags).SetValue(null,status);
  typeof(EpicOriginalReader).GetField("healthChecked",flags).SetValue(null,false);
  var method=typeof(EpicOriginalReader).GetMethod("Read",Hidden);
  if(method==null)throw new Exception("Reviewed binding provenance archive reader unavailable");
  var units=new Dictionary<ulong,Resource>();var materials=new Dictionary<ulong,Resource>();
  var wantedUnits=new HashSet<ulong>();var preferred=new List<string>();
  foreach(var item in requests){wantedUnits.Add(item.Unit);preferred.Add(item.Preferred);}
  var collisions=new Dictionary<ulong,HashSet<ulong>>{{UnitType,new HashSet<ulong>()},{MaterialType,new HashSet<ulong>()},{TextureType,new HashSet<ulong>()}};
  string scopeMetadata=null;List<LooseFile> effectiveFiles=null;
  var looseMaterials=new Dictionary<ulong,List<LooseCandidate>>();
  using(var reader=new EpicOriginalReader(game)) {
   var entries=(IDictionary)typeof(EpicOriginalReader).GetField("entries",Hidden).GetValue(reader);
   var names=new List<string>();
   foreach(string name in entries.Keys) {
    ulong parsed;if(name.Length==16 && ulong.TryParse(name,NumberStyles.AllowHexSpecifier,CultureInfo.InvariantCulture,out parsed))names.Add(name);
   }
   names.Sort(StringComparer.Ordinal);var archives=new Dictionary<string,Archive>(StringComparer.Ordinal);
   foreach(string archive in Order(names,preferred)) {
    Check(status,clock,ownerPID);
    File.WriteAllText(status,"Reading binding provenance: "+units.Count+"/"+requests.Count+" units; "+visited+" TOCs, "+rows+" rows");
    byte[] header=Read(reader,method,archive,0,72,status,clock,ownerPID);
    if(U(header,0)!=0xf0000011)throw new Exception("Binding provenance archive TOC header invalid: "+archive);
    uint types=U(header,4),count=U(header,8);
    if(types>4096 || count>100000)throw new Exception("Binding provenance TOC count bounds");
    int start=checked(72+(int)types*32),size=checked(start+(int)count*80);
    metadata+=72L+size;rows+=count;
    if(metadata>MetadataBudget || rows>RowBudget)throw new Exception("Binding provenance TOC metadata budget exceeded");
    byte[] toc=Read(reader,method,archive,0,size,status,clock,ownerPID);
    var info=new Archive{Name=archive,Hash=Digest(toc),Size=size,Start=start,Count=(int)count};archives.Add(archive,info);visited++;
    for(int i=0;i<count;i++) {
     Check(status,clock,ownerPID);int at=start+i*80;ulong resource=Q(toc,at),type=Q(toc,at+8);
     HashSet<ulong> collision;
     if(collisions.TryGetValue(type,out collision) && collision.Add(resource)) {
      metadata+=24;if(metadata>MetadataBudget)throw new Exception("Binding provenance collision metadata budget exceeded");
     }
     if(type==MaterialType)info.Materials=true;
     if(type==UnitType && wantedUnits.Contains(resource)) {
      // A duplicate is a temporary comparison buffer, not another output item.
      Resource old;long retained=units.TryGetValue(resource,out old)?total-old.Bytes:total;
      Remember(units,Load(reader,method,archive,toc,at,status,clock,ownerPID,retained),ref total);
     }
    }
   }
   if(units.Count!=wantedUnits.Count)throw new Exception("Exact binding provenance unit resources missing: "+units.Count+"/"+wantedUnits.Count);
   if(effective) {
    long retained;
    scopeMetadata=ScanLoose(game,units,materials,collisions,ref metadata,ref rows,total,status,clock,ownerPID,true,looseMaterials,out effectiveFiles,out retained);
    total=retained;
   }
   var wantedMaterials=new HashSet<ulong>();var materialPreferred=new List<string>();
   foreach(var item in requests) {
    var unit=units[item.Unit];materialPreferred.Add(unit.Archive);
    foreach(ulong material in UnitMaterials(unit))wantedMaterials.Add(material);
   }
   materialPreferred.AddRange(preferred);
   foreach(string archive in Order(names,materialPreferred)) {
    var info=archives[archive];if(!info.Materials)continue;
    Check(status,clock,ownerPID);
    File.WriteAllText(status,"Reading binding provenance materials: "+materials.Count+"/"+wantedMaterials.Count+"; full collision catalog "+rows+" rows");
    byte[] toc=Read(reader,method,archive,0,info.Size,status,clock,ownerPID);
    if(Digest(toc)!=info.Hash)throw new Exception("Binding provenance archive TOC changed during extraction");
    for(int i=0;i<info.Count;i++) {
     int at=info.Start+i*80;ulong resource=Q(toc,at);
     if(Q(toc,at+8)!=MaterialType || !wantedMaterials.Contains(resource))continue;
     Resource old;long retained=materials.TryGetValue(resource,out old)?total-old.Bytes:total;
     Remember(materials,Load(reader,method,archive,toc,at,status,clock,ownerPID,retained),ref total);
    }
   }
   if(effective) {
    var selectedLoose=new Dictionary<ulong,Resource>();
    foreach(ulong resource in wantedMaterials) {
     List<LooseCandidate> candidates;if(!looseMaterials.TryGetValue(resource,out candidates))continue;
     foreach(var locator in candidates) {
      Resource old;long retained=materials.TryGetValue(resource,out old)?total-old.Bytes:total;
      var candidate=LooseResource(locator.Archive,locator.Main,locator.GPU,locator.Stream,locator.TOC,locator.At,status,clock,ownerPID,retained);
      Effective(materials,selectedLoose,candidate,ref total);
     }
    }
    foreach(var file in effectiveFiles)Unchanged(file);
   }
   if(materials.Count!=wantedMaterials.Count)throw new Exception("Exact binding provenance material resources missing: "+materials.Count+"/"+wantedMaterials.Count);
  }
  // Stock mode retains packed originals and refuses differing loose overrides.
  // Explicit weapon_effective mode preserves the unambiguous scoped Unit and
  // linked Material triplets. External archives/runtime-only changes are outside this scope.
  if(!effective) {
   List<LooseFile> observed;long retained;
   scopeMetadata=ScanLoose(game,units,materials,collisions,ref metadata,ref rows,total,status,clock,ownerPID,false,looseMaterials,out observed,out retained);
  }
  // Nothing is published until every requested resource, all duplicates, the
  // unit tables, and the complete collision catalog have passed validation.
  var ordered=new List<Resource>();ordered.AddRange(units.Values);ordered.AddRange(materials.Values);
  ordered.Sort(delegate(Resource a,Resource b){int type=a.Type.CompareTo(b.Type);return type!=0?type:a.Name.CompareTo(b.Name);});
  foreach(var collision in collisions.Values)if(metadata+collision.Count*8L>MetadataBudget)
   throw new Exception("Binding provenance collision sorting budget exceeded");
  var manifest=new StringBuilder();var sourceManifest=new StringBuilder();
  string scopeHash=scopeMetadata.Split('\n')[2];
  foreach(var item in ordered) {
   Check(status,clock,ownerPID);string basename=Hex(item.Name)+"."+Hex(item.Type);
   AtomicBytes(Child(output,basename+".main"),item.Main);AtomicBytes(Child(output,basename+".toc"),item.TOC);
   if(item.GPU.Length!=0)AtomicBytes(Child(output,basename+".gpu"),item.GPU);
   if(item.Stream.Length!=0)AtomicBytes(Child(output,basename+".stream"),item.Stream);
   manifest.Append(Hex(item.Type)).Append('\t').Append(Hex(item.Name)).Append('\t').Append(item.Archive).Append('\t')
    .Append(basename+".main").Append('\t').Append(item.GPU.Length==0?"-":basename+".gpu").Append('\t')
    .Append(item.Stream.Length==0?"-":basename+".stream").Append('\t').Append(basename+".toc").Append('\t')
    .Append(Digest(item.Main)).Append('\t').Append(item.GPU.Length==0?"-":Digest(item.GPU)).Append('\t')
    .Append(item.Stream.Length==0?"-":Digest(item.Stream)).Append('\n');
   if(effective)sourceManifest.Append(Hex(item.Type)).Append('\t').Append(Hex(item.Name)).Append('\t')
    .Append(item.SourceFile==null?"packed":"loose").Append('\t').Append(item.SourceFile??item.Archive).Append('\t')
    .Append(scopeHash).Append('\n');
  }
  var typesOrdered=new List<ulong>(collisions.Keys);typesOrdered.Sort();
  Atomic(Child(output,"collisions.tsv"),delegate(FileStream stream){
   using(var writer=new StreamWriter(stream,new UTF8Encoding(false),65536,true)) {
    foreach(ulong type in typesOrdered) {
     Check(status,clock,ownerPID);var ids=new List<ulong>(collisions[type]);
     ids.Sort();foreach(ulong resource in ids){Check(status,clock,ownerPID);writer.Write(Hex(type));writer.Write('\t');writer.Write(Hex(resource));writer.Write('\n');}
    }
    writer.Flush();
   }
  });
  long collisionCount=0;foreach(var collision in collisions.Values)collisionCount+=collision.Count;
  string collisionPath=Child(output,"collisions.tsv");
  if(new FileInfo(collisionPath).Length!=collisionCount*34L)throw new Exception("Binding provenance collision catalog row size differs");
  AtomicBytes(Child(output,"collisions.meta"),new UTF8Encoding(false).GetBytes(collisionCount.ToString(CultureInfo.InvariantCulture)+"\n"
   +DigestFile(collisionPath,status,clock,ownerPID)+"\n"));
  AtomicBytes(Child(output,"resources.tsv"),new UTF8Encoding(false).GetBytes(manifest.ToString()));
  AtomicBytes(Child(output,"scope.meta"),new UTF8Encoding(false).GetBytes(scopeMetadata));
  if(effective)AtomicBytes(Child(output,"sources.tsv"),new UTF8Encoding(false).GetBytes(sourceManifest.ToString()));
  Check(status,clock,ownerPID);
  File.WriteAllText(status,"Binding provenance ready: "+units.Count+" units, "+materials.Count+" materials, "+total+" raw bytes; full "+visited+" TOCs, "+rows+" rows");
  return ordered.Count;
 }
}
