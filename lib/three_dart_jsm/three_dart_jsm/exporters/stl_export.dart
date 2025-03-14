/**
 * @author kovacsv / http://kovacsv.hu/
 * @author mrdoob / http://mrdoob.com/
 */

import 'package:openworld/three_dart/three_dart.dart';

class STLExporter{
  String _output = '';
  bool _usingParse = false;

  STLExporter();

  Vector3 _computeNormal(Vector3 va, Vector3 vb, Vector3 vc) {
    Vector3 cb = Vector3().copy(vc);
    Vector3 ab = Vector3().copy(vb);

    ab.sub(va);
    cb.sub(vb);
    cb.cross(ab);
    if(cb.x != 0 && cb.y != 0 && cb.z != 0) {
      cb.normalize();
    }

    return cb;
  }

  String parseMesh(Mesh object){
    if(!_usingParse){
      _output = 'solid exported\n';
    }
    BufferGeometry? geometry = object.geometry;
    final Float32BufferAttribute? vertices = geometry?.getAttribute('position');
    final indices = geometry?.getIndex();
    if(indices != null){
      for(int i = 0, l = indices.length; i < l; i+=3) {
        final faces = [indices.getX(i)!.toInt(), indices.getX(i+1)!.toInt(), indices.getX(i+2)!.toInt()];
        String verts = '';
        List<Vector3> vecsToNormal = [];
        for(int j = 0; j < 3; j ++){
          vecsToNormal.add(Vector3(vertices!.getX(faces[j])!.toDouble(),vertices.getY(faces[j])!.toDouble(),vertices.getZ(faces[j])!.toDouble()));
          verts += '\t\t\tvertex ${vecsToNormal[j].x} ${vecsToNormal[j].y} ${vecsToNormal[j].z}\n';
        }
        Vector3 toNormal = _computeNormal(vecsToNormal[0],vecsToNormal[1],vecsToNormal[2]);
        _output += '\tfacet normal ${toNormal.x} ${toNormal.y} ${toNormal.z}\n';
        _output += '\t\touter loop\n';
        _output += verts;
        _output += '\t\tendloop\n';
        _output += '\tendfacet\n';
      }
    }

    return _output;
  }

  String parse(Scene scene) {
    _usingParse = true;
    _output = 'solid exported\n';

    scene.traverse((object) {
      if(object is Mesh) {
        parseMesh(object);
      }
    });

    _output += 'endsolid exported\n';
    _usingParse = false;
    return _output;
  }
}