export type Transform = {number} -- x,y,z,qx,qy,qz,qw
export type Track = {id:string,time:number,speed:number,weight:number,priority:number,looped:number}
export type Frame = {
    time:number, root:Transform, camera:Transform, velocity:{number}, angular:{number},
    geometry:{number}, humanoid:{number}, flags:{number}, tracks:{Track},
}
export type Node = {parent:number,frame:Frame}
export type Metadata = {map:string,author:string,spawn:string,created:number}
-- Reserved interface; no world rewind implementation in this release.
export type WorldStateProvider = {
    Capture:(self:WorldStateProvider)->any,
    Restore:(self:WorldStateProvider, snapshot:any)->(),
    Destroy:(self:WorldStateProvider)->(),
}
return function() return {} end
