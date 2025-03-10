part of jsm_loader;

/**
 * Description: A THREE loader for STL ASCII files, as created by Solidworks and other CAD programs.
 *
 * Supports both binary and ASCII encoded files, with automatic detection of type.
 *
 * The loader returns a non-indexed buffer geometry.
 *
 * Limitations:
 *  Binary decoding supports "Magics" color format (http://en.wikipedia.org/wiki/STL_(file_format)#Color_in_binary_STL).
 *  There is perhaps some question as to how valid it is to always assume little-endian-ness.
 *  ASCII decoding assumes file is UTF-8.
 *
 * Usage:
 *  const loader = new STLLoader();
 *  loader.load( './models/stl/slotted_disk.stl', function ( geometry ) {
 *    scene.add( new THREE.Mesh( geometry ) );
 *  });
 *
 * For binary STLs geometry might contain colors for vertices. To use it:
 *  // use the same code to load STL as above
 *  if (geometry.hasColors) {
 *    material = new THREE.MeshPhongMaterial({ opacity: geometry.alpha, vertexColors: true });
 *  } else { .... }
 *  const mesh = new THREE.Mesh( geometry, material );
 *
 * For ASCII STLs containing multiple solids, each solid is assigned to a different group.
 * Groups can be used to assign a different color by defining an array of materials with the same length of
 * geometry.groups and passing it to the Mesh constructor:
 *
 * const mesh = new THREE.Mesh( geometry, material );
 *
 * For example:
 *
 *  const materials = [];
 *  const nGeometryGroups = geometry.groups.length;
 *
 *  const colorMap = ...; // Some logic to index colors.
 *
 *  for (let i = 0; i < nGeometryGroups; i++) {
 *
 *		const material = new THREE.MeshPhongMaterial({
 *			color: colorMap[i],
 *			wireframe: false
 *		});
 *
 *  }
 *
 *  materials.push(material);
 *  const mesh = new THREE.Mesh(geometry, materials);
 */


class STLLoader extends Loader {
	STLLoader([manager]):super(manager);

  loadAsync(url) async {
    final completer = Completer();

    load(url, (buffer) {
      completer.complete(buffer);
    });

    return completer.future;
  }

	void load( url, onLoad, [onProgress, onError ]){
		final scope = this;

		final loader = FileLoader(this.manager);
		loader.setPath(this.path);
		loader.setResponseType('arraybuffer');
		loader.setRequestHeader(this.requestHeader);
		loader.setWithCredentials(this.withCredentials);

		loader.load( url, 
      (text) {
			  onLoad(scope.parse(text));
		  },
      onProgress, 
      onError 
    );
	}
  BufferGeometry parseBinary(Uint8List data) {
    final reader = ByteData.view(data.buffer);
    final faces = reader.getUint32(80, Endian.little);

    double r = 0;
    double g = 0;
    double b = 0;
    bool hasColors = false;
    late Float32Array colors;
    double defaultR = 0;
    double defaultG = 0;
    double defaultB = 0; 
    double alpha = 0;

    // process STL header
    // check for default color in header ("COLOR=rgba" sequence).

    for (int index = 0; index < 80 - 10; index ++ ) {
      if ((reader.getUint32(index) == 0x434F4C4F /*COLO*/ ) &&
        (reader.getUint8( index + 4 ) == 0x52 /*'R'*/ ) &&
        (reader.getUint8( index + 5 ) == 0x3D /*'='*/ )
      ){

        hasColors = true;
        colors = Float32Array( faces * 3 * 3 );

        defaultR = reader.getUint8( index + 6 ) / 255;
        defaultG = reader.getUint8( index + 7 ) / 255;
        defaultB = reader.getUint8( index + 8 ) / 255;
        alpha = reader.getUint8( index + 9 ) / 255;
      }
    }

    const dataOffset = 84;
    const faceLength = 12 * 4 + 2;

    final geometry = BufferGeometry();

    final vertices = Float32Array( faces * 3 * 3 );
    final normals = Float32Array( faces * 3 * 3 );

    final color = Color();

    for(int face = 0; face < faces; face ++){

      final start = dataOffset + face * faceLength;
      final normalX = reader.getFloat32( start, Endian.little);
      final normalY = reader.getFloat32( start + 4, Endian.little);
      final normalZ = reader.getFloat32( start + 8, Endian.little);

      if ( hasColors ) {
        final packedColor = reader.getUint16( start + 48, Endian.little);
        if ( ( packedColor & 0x8000 ) == 0 ) {
          // facet has its own unique color
          r = ( packedColor & 0x1F ) / 31;
          g = ( ( packedColor >> 5 ) & 0x1F ) / 31;
          b = ( ( packedColor >> 10 ) & 0x1F ) / 31;
        } 
        else {
          r = defaultR;
          g = defaultG;
          b = defaultB;
        }
      }

      for(int i = 1; i <= 3; i ++ ) {

        final vertexstart = start + i * 12;
        final componentIdx = ( face * 3 * 3 ) + ( ( i - 1 ) * 3 );

        vertices[componentIdx] = reader.getFloat32( vertexstart, Endian.little);
        vertices[componentIdx + 1] = reader.getFloat32( vertexstart + 4, Endian.little);
        vertices[componentIdx + 2] = reader.getFloat32( vertexstart + 8, Endian.little);

        normals[componentIdx] = normalX;
        normals[componentIdx + 1] = normalY;
        normals[componentIdx + 2] = normalZ;

        if ( hasColors ) {
          color.setRGB(r, g, b).convertSRGBToLinear();
          colors[componentIdx] = color.r;
          colors[componentIdx + 1] = color.g;
          colors[componentIdx + 2] = color.b;
        }
      }
    }

    geometry.setAttribute('position', Float32BufferAttribute(vertices,3));
    geometry.setAttribute('normal', Float32BufferAttribute(normals,3));

    if(hasColors){
      geometry.setAttribute('color', Float32BufferAttribute(colors,3));
      //geometry.hasColors = true;
      //geometry.alpha = alpha;
    }

    return geometry;
  }

  BufferGeometry parseASCII(String data) {
    final geometry = BufferGeometry();
    int faceCounter = 0;

    final List<double> vertices = [];
    final List<double> normals = [];
    final List<int> indices = [];
    final groupNames = [];

    int groupCount = 0;
    int startVertex = 0;
    int endVertex = 0;

    final lines = data.split('\n');
    int vertexCountPerFace = 0;
    int normalCountPerFace = 0;
    for (var line in lines) {
      List<String> parts = line.trim().split(RegExp(r"\s+"));
      switch (parts[0]) {
        case 'solid':
          groupNames.add(parts[0].replaceAll('solid ', ''));
          startVertex = endVertex;
          break;
        case 'endsolid':
          int start = startVertex;
          int count = endVertex - startVertex;

          geometry.userData['groupNames'] = groupNames;

          geometry.addGroup( start, count, groupCount );
          groupCount++;
          break;
        case 'facet':
          if(parts[1].contains('normal')){
            normals.addAll([double.parse(parts[2]),double.parse(parts[3]),double.parse(parts[4])]);
            normalCountPerFace++;
          }
          faceCounter++;
          break;
        case 'endfacet':
          // every face have to own ONE valid normal
          if(normalCountPerFace > 1){
            throw( 'THREE.STLLoader: Something isn\'t right with the normal of face number $faceCounter');
          }

          // each face have to own THREE valid vertices
          if(vertexCountPerFace != 3){
            print(vertexCountPerFace);
            throw( 'THREE.STLLoader: Something isn\'t right with the vertices of face number $faceCounter');
          }
          vertexCountPerFace = 0;
          normalCountPerFace = 0;
          break;
        case 'vertex':
          // the name for the group. eg: g front cube
          vertices.addAll([double.parse(parts[1]),double.parse(parts[2]),double.parse(parts[3])]);
          vertexCountPerFace++;
          endVertex++;
          int k = vertices.length;
          if(k%3 == 0 && k != 0){
            indices.addAll([k-3,k-2,k-1,k-3,k-2,k-1]);
          }
          break;
        default:
      }
    }

    geometry.setAttribute('position', Float32BufferAttribute(Float32Array.fromList(vertices),3));
    geometry.setAttribute('normal', Float32BufferAttribute(Float32Array.fromList(normals),3));
    geometry.setIndex(indices);

    return geometry;
  }
	BufferGeometry parse(data, [String? path, Function? onLoad, Function? onError]) {
		bool matchDataViewAt( query, reader, offset ) {
			// Check if each byte in query matches the corresponding byte from the current offset
			for (int i = 0, il = query.length; i < il; i ++ ) {
				if ( query[ i ] != reader.getUint8( offset + i ) ) return false;
			}
			return true;
		}
		bool isBinary(Uint8List data){
			final reader = ByteData.view(data.buffer);
			const face_size = ( 32 / 8 * 3 ) + ( ( 32 / 8 * 3 ) * 3 ) + ( 16 / 8 );
			final n_faces = reader.getUint32( 80, Endian.little);
			final expect = 80 + ( 32 / 8 ) + ( n_faces * face_size );

			if (expect == reader.lengthInBytes) {
				return true;
			}

			// An ASCII STL data must begin with 'solid ' as the first six bytes.
			// However, ASCII STLs lacking the SPACE after the 'd' are known to be
			// plentiful.  So, check the first 5 bytes for 'solid'.

			// Several encodings, such as UTF-8, precede the text with up to 5 bytes:
			// https://en.wikipedia.org/wiki/Byte_order_mark#Byte_order_marks_by_encoding
			// Search for "solid" to start anywhere after those prefixes.

			// US-ASCII ordinal values for 's', 'o', 'l', 'i', 'd'

			const solid = [ 115, 111, 108, 105, 100 ];

			for (int off = 0; off < 5; off ++ ) {
				// If "solid" text is matched to the current offset, declare it to be an ASCII STL.
				if(matchDataViewAt(solid, reader, off)){
          return false;
        }
			}
			// Couldn't find "solid" text at the beginning; it is binary STL.
			return true;
		}

		String ensureString(buffer){
			if(buffer is String) {
				return buffer;
			}

			return String.fromCharCodes(buffer);
		}
		Uint8List ensureBinary(buffer) {
			if (buffer is String) {
				final array_buffer = Uint8List(buffer.length);
				for (int i = 0; i < buffer.length; i ++ ) {
					array_buffer[i] = buffer.codeUnits[i] & 0xff; // implicitly assumes little-endian
				}
				return array_buffer;
			} 
      else {
				return buffer;
			}
		}

		// start
		final binData = ensureBinary(data);

		return isBinary(binData)?parseBinary(binData):parseASCII(ensureString(data));
	}
}