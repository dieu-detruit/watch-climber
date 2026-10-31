#!/usr/bin/env node
// Download current GSI DEM10B PNG tiles and make the exact offline elevation grid.
// No fabricated elevations or route coordinates. Deterministic pixel sampling.
import { createHash } from "node:crypto";
import { inflateSync } from "node:zlib";
import { mkdir, writeFile } from "node:fs/promises";

const Z = 14;
const X0 = 14530, X1 = 14534, Y0 = 6439, Y1 = 6443;
const STRIDE = 2;
const output = "public/terrain";
const tileDir = output + "/hanno-tiles";

function decodePNG(bytes) {
  const magic = Buffer.from([137,80,78,71,13,10,26,10]);
  if (!bytes.subarray(0,8).equals(magic)) throw new Error("Not a PNG");
  let offset = 8, width, height, depth, colorType, interlace;
  const compressed = [];
  let palette = null;
  while (offset + 12 <= bytes.length) {
    const len = bytes.readUInt32BE(offset);
    const type = bytes.toString("ascii", offset+4, offset+8);
    if (offset + 12 + len > bytes.length) throw new Error("Truncated PNG");
    const chunk = bytes.subarray(offset+8,offset+8+len);
    if (type === "IHDR") {
      width=chunk.readUInt32BE(0);
      height=chunk.readUInt32BE(4);
      depth=chunk[8];
      colorType=chunk[9];
      interlace=chunk[12];
    } else if (type === "IDAT") compressed.push(chunk);
    else if (type === "PLTE") palette=chunk;
    offset += len+12;
    if (type === "IEND") break;
  }
  if(width!==256 || height!==256 || depth!==8 || interlace!==0 ||
    ![2,3,6].includes(colorType)) throw new Error(
      "Unsupported GSI PNG format: "+JSON.stringify({width,height,depth,colorType,interlace}));
  const bpp = colorType===2 ? 3 : colorType===6 ? 4 : 1;
  const rowLength=width*bpp;
  const raw=inflateSync(Buffer.concat(compressed));
  if(raw.length !== height*(rowLength+1)) throw new Error("Bad PNG decoded byte length");
  const rgb=Buffer.alloc(width*height*3);
  let scan=0,previous=Buffer.alloc(rowLength);
  for(let y=0;y<height;y++){
    const filter=raw[scan++];
    const current=Buffer.alloc(rowLength);
    for(let i=0;i<rowLength;i++){
      const a=i>=bpp?current[i-bpp]:0, b=previous[i], c=i>=bpp?previous[i-bpp]:0;
      let predictor=0;
      switch(filter){
        case 0: predictor=0; break;
        case 1: predictor=a; break;
        case 2: predictor=b; break;
        case 3: predictor=Math.floor((a+b)/2); break;
        case 4: {
          const p=a+b-c, pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);
          predictor=pa<=pb&&pa<=pc?a:pb<=pc?b:c;
          break;
        }
        default: throw new Error("Unknown PNG filter "+filter);
      }
      current[i]=(raw[scan++]+predictor)&255;
    }
    for(let x=0;x<width;x++){
      const out=(y*width+x)*3;
      if(colorType===3){
        if(!palette || current[x]*3+2>=palette.length) throw new Error("Invalid palette");
        rgb[out]=palette[current[x]*3];
        rgb[out+1]=palette[current[x]*3+1];
        rgb[out+2]=palette[current[x]*3+2];
      }else{
        rgb[out]=current[x*bpp];
        rgb[out+1]=current[x*bpp+1];
        rgb[out+2]=current[x*bpp+2];
      }
    }
    previous=current;
  }
  return rgb;
}

function heightFromRGB(r,g,b) {
  const encoded=(r<<16)+(g<<8)+b;
  if(encoded===0x800000) return null;
  const centimeters=encoded<0x800000?encoded:encoded-0x1000000;
  return Math.round(centimeters/10)/10;
}

function latitude(y){
  return Math.atan(Math.sinh(Math.PI*(1-2*y/2**Z)))*180/Math.PI;
}
function longitude(x){return x/2**Z*360-180;}
async function getTile(x,y) {
  const url=`https://cyberjapandata.gsi.go.jp/xyz/dem_png/${Z}/${x}/${y}.png`;
  let last;
  for(let attempt=1;attempt<=3;attempt++){
    try{
      const response=await fetch(url,{
        signal:AbortSignal.timeout(25000),
        headers:{"User-Agent":"WatchClimber/0.1 (personal offline GSI DEM)"}
      });
      if(!response.ok) throw new Error(`GSI returned HTTP ${response.status} for ${url}`);
      const bytes=Buffer.from(await response.arrayBuffer());
      const rgb=decodePNG(bytes);
      return {bytes,rgb,url,x,y};
    }catch(error){
      last=error;
      if(attempt<3) await new Promise(resolve=>setTimeout(resolve,1000*attempt));
    }
  }
  throw last;
}

await mkdir(tileDir,{recursive:true});
const tiles=new Map(), sources=[];
for(let y=Y0;y<=Y1;y++){
  for(let x=X0;x<=X1;x++){
    const tile=await getTile(x,y);
    const filename=`${Z}-${x}-${y}.png`;
    await writeFile(`${tileDir}/${filename}`,tile.bytes);
    tiles.set(`${x}/${y}`,tile.rgb);
    sources.push({url:tile.url,file:`hanno-tiles/${filename}`,
      sha256:createHash("sha256").update(tile.bytes).digest("hex")});
    console.log("Downloaded",x,y,tile.bytes.length);
  }
}
const columns=(X1-X0+1)*256/STRIDE,rows=(Y1-Y0+1)*256/STRIDE;
const heights=[];
let minimum=Infinity,maximum=-Infinity,missing=0;
for(let row=0;row<rows;row++){
  const py=row*STRIDE;
  for(let col=0;col<columns;col++){
    const px=col*STRIDE;
    const rgb=tiles.get(`${X0+Math.floor(px/256)}/${Y0+Math.floor(py/256)}`);
    const local=((py%256)*256+px%256)*3;
    const h=heightFromRGB(rgb[local],rgb[local+1],rgb[local+2]);
    heights.push(h);
    if(h===null) missing++;
    else {minimum=Math.min(minimum,h); maximum=Math.max(maximum,h);}
  }
}
if(!Number.isFinite(minimum) || missing>heights.length*0.4){
  throw new Error(`Terrain missing too much data: ${missing}/${heights.length}`);
}
const payload={
  name:"飯能・多峯主山・天覧山・宮沢湖周辺",
  source:"国土地理院 DEM10B PNG標高タイル",
  sourceUrl:"https://maps.gsi.go.jp/development/ichiran.html",
  specUrl:"https://maps.gsi.go.jp/development/demtile.html",
  fetchedAt:new Date().toISOString(),
  zoom:Z,
  tileOrigin:[X0,Y0],
  pixelStride:STRIDE,
  columns,rows,
  bounds:{
    west:longitude(X0+0.5/256),
    east:longitude(X0+((columns-1)*STRIDE+0.5)/256),
    north:latitude(Y0+0.5/256),
    south:latitude(Y0+((rows-1)*STRIDE+0.5)/256)
  },
  heightRange:[minimum,maximum],
  missingCells:missing,
  processing:"GSI PNG DEM10BのRGB標高値を復号。2画素間隔、標高0.1m丸め。欠損はnull。",
  heights
};
await writeFile(`${output}/hanno.json`,JSON.stringify(payload)+"\n");
await writeFile(`${output}/hanno-sources.json`,JSON.stringify(sources,null,2)+"\n");
console.log(JSON.stringify({...payload,heights:undefined},null,2));
