// Read only the exact installed-game camo atlas mip used by material LUTs.
// Resource/layout proof: HD2SDK 5a886256, verified on the current local atlas.
using System;
using System.IO;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;

public static class EpicCamoPreviewReader {
 const ulong Atlas = 0xeecf271273d7090cUL, TextureType = 0xcd4238c6a0c69e32UL;
 const string OwnerArchive = "18235e0c9ec0e636";
 const int Width = 256, Layers = 6, Mips = 9, Thumbnail = 16, Bytes = 1024;
 const long MetadataBudget = 512L * 1024 * 1024, RowBudget = 6000000;
 const int SliceStride = 349524, MipOffset = 348160, GPUBytes = 2097144;
 static uint U(byte[] data,int at) {
  if(at<0 || at>data.Length-4)throw new Exception("Camo header integer bounds");
  return BitConverter.ToUInt32(data,at);
 }
 static ulong Q(byte[] data,int at) {
  if(at<0 || at>data.Length-8)throw new Exception("Camo resource offset bounds");
  return BitConverter.ToUInt64(data,at);
 }
 static void Check(string status,Stopwatch clock) {
  if(clock.Elapsed.TotalSeconds>180)throw new Exception("Camo lookup exceeded 180 seconds");
  if(File.Exists(status+".cancel"))throw new Exception("Camo extraction canceled");
 }
 static byte[] Read(EpicOriginalReader reader,MethodInfo method,string archive,ulong at,int size,string status,Stopwatch clock) {
  Check(status,clock);byte[] data;
  try {data=(byte[])method.Invoke(reader,new object[]{archive,at,size});}
  catch(TargetInvocationException error){throw error.InnerException ?? error;}
  Check(status,clock);
  if(data==null || data.Length!=size)throw new Exception("Short camo resource read");
  return data;
 }
 static void Atomic(string path,byte[] data) {
  string temporary=path+"."+Guid.NewGuid().ToString("N")+".pending";
  try {
   using(var file=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
    file.Write(data,0,data.Length);file.Flush(true);
   }
   if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);
  } finally {if(File.Exists(temporary))File.Delete(temporary);}
 }
 public static int Run(string gameData,string destination,int ownerPID,string status) {
  string game=Path.GetFullPath(gameData).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
  string output=Path.GetFullPath(destination);
  if(output.StartsWith(game,StringComparison.OrdinalIgnoreCase))throw new Exception("Camo cache cannot be inside game data");
  if(!Directory.Exists(game) || !Directory.Exists(output))throw new Exception("Camo preview directories unavailable");
  var flags=BindingFlags.Static|BindingFlags.NonPublic;
  typeof(EpicOriginalReader).GetField("owner",flags).SetValue(null,ownerPID);
  typeof(EpicOriginalReader).GetField("progress",flags).SetValue(null,status);
  typeof(EpicOriginalReader).GetField("healthChecked",flags).SetValue(null,false);
  var hidden=BindingFlags.Instance|BindingFlags.NonPublic;
  var method=typeof(EpicOriginalReader).GetMethod("Read",hidden);
  if(method==null)throw new Exception("Reviewed camo archive reader unavailable");
  var clock=Stopwatch.StartNew();byte[][] masks=null;long metadata=0,rows=0;int visited=0;
  using(var reader=new EpicOriginalReader(game)) {
   metadata=((byte[])typeof(EpicOriginalReader).GetField("data",hidden).GetValue(reader)).Length;
   var entries=(IDictionary)typeof(EpicOriginalReader).GetField("entries",hidden).GetValue(reader);
   var names=new List<string>();
   foreach(string name in entries.Keys) {
    ulong parsed;if(name.Length==16 && ulong.TryParse(name,NumberStyles.HexNumber,CultureInfo.InvariantCulture,out parsed))names.Add(name);
   }
   names.Sort(StringComparer.Ordinal);if(names.Remove(OwnerArchive))names.Insert(0,OwnerArchive);
   foreach(string archive in names) {
    Check(status,clock);
    File.WriteAllText(status,"Reading camo atlas: "+visited+" TOCs, "+rows+" rows");
    byte[] header=Read(reader,method,archive,0,72,status,clock);metadata+=72;
    if(U(header,0)!=0xf0000011)continue;
    uint types=U(header,4),count=U(header,8);
    if(types>4096 || count>100000)throw new Exception("Camo TOC count bounds");
    int start=checked(72+(int)types*32),size=checked(start+(int)count*80);
    if(metadata+size>MetadataBudget || rows+count>RowBudget)throw new Exception("Camo metadata budget exceeded");
    byte[] toc=Read(reader,method,archive,0,size,status,clock);metadata+=size;rows+=count;visited++;
    for(int i=0;i<count;i++) {
     Check(status,clock);int at=start+i*80;
     if(Q(toc,at)!=Atlas || Q(toc,at+8)!=TextureType)continue;
     uint mainSize=U(toc,at+56);
     if(mainSize<340 || mainSize>16*1024*1024)throw new Exception("Camo texture header byte budget");
     if(U(toc,at+60)!=0 || U(toc,at+64)!=GPUBytes)throw new Exception("Camo atlas GPU layout changed");
     byte[] body=Read(reader,method,archive,Q(toc,at+16),340,status,clock);
     if(U(body,192)!=0x20534444 || U(body,196)!=124 || U(body,268)!=32 || U(body,276)!=0x30315844
        || U(body,204)!=Width || U(body,208)!=Width || U(body,220)!=Mips || U(body,320)!=28
        || U(body,324)!=3 || U(body,328)!=0 || U(body,332)!=Layers)
      throw new Exception("Camo atlas format changed");
     ulong gpu=Q(toc,at+32);masks=new byte[Layers][];
     for(int layer=0;layer<Layers;layer++) {
      int relative=checked(layer*SliceStride+MipOffset);
      if(relative<0 || relative>GPUBytes-Bytes)throw new Exception("Camo mip leaves resource");
      masks[layer]=Read(reader,method,archive+".gpu_resources",checked(gpu+(ulong)relative),Bytes,status,clock);
     }
     break;
    }
    if(masks!=null)break;
   }
  }
  if(masks==null)throw new Exception("Exact camo atlas resource missing");
  for(int layer=0;layer<Layers;layer++) {
   Check(status,clock);string name="mask-"+layer.ToString(CultureInfo.InvariantCulture)+".rgba";
   string path=Path.GetFullPath(Path.Combine(output,name));
   if(!path.StartsWith(output.TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Camo cache path leaves version folder");
   Atomic(path,masks[layer]);
  }
  File.WriteAllText(status,"Camo previews ready: "+Layers+" exact "+Thumbnail+"x"+Thumbnail+" RGBA8 mips; "+visited+" TOCs");
  return Layers;
 }
}
