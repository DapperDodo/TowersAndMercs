package core;

import openfl.geom.Rectangle;
import openfl.geom.Point;

import interfaces.IVision;

/*
	add Grid typedef just to make this class more readable
	Grid is a two dimensional array of IVisionTiles
*/
typedef Grid = Array<Array<IVisionTile>>;


/*
	An instance of this class should be attached to each player in the game
*/
class Vision implements IVisionServer
{
	// size of each Vision Tile in pixels
	private var tilesize : Int = 16;

	// map dimensions, map name etc. can be gotten from this
	private var mapData : MapData;

	// the grid of vision tiles
	private var tiles : Grid;

	// number of rows (height in tiles)
	private var rows : Int;

	// number of cols (width in tiles)
	private var cols : Int;

	// array of objects interested in vision changes
	private var clientRegistry : Array<IVisionClient>;

	// cache of vision 'stamps', one for each radius used in the game
	private var radiusGridCache : Map<String, Grid>;


	public function new(mapData : MapData)
	{
		this.mapData = mapData;
		clientRegistry = new Array<IVisionClient>();
		radiusGridCache = new Map<String, Grid>();
	}


	/*
		called when map data is loaded
		initialize the map visibility 
		start fully unexplored
		covers one half of the map (enemy's side)
	*/
	public function init()
	{
		cols = Math.ceil(mapData.getWidth() / tilesize);
		rows = Math.ceil((mapData.getHeight() / 2) / tilesize); // the division by 2 is because the fog of war only covers HALF of the map

		//trace("Vision.init : cols, rows = (" + cols + ", " + rows + ")");

		tiles = newGrid(rows, cols);
	}

	/*
		register objects that want to know about vision state changes
	*/
	public function register(client : IVisionClient)
	{
		if(clientRegistry.indexOf(client) == -1)
		{
			clientRegistry.push(client);
		}
	}

	/*
		unregister objects that no longer want to know about vision state changes
	*/
	public function unregister(client : IVisionClient)
	{
		if(clientRegistry.indexOf(client) >= 0)
		{
			clientRegistry.remove(client);
		}
	}

	/*
		friendly units can let the vision system know where they are providing vision for the player
		the vision system will track their current field of vision (Full)
		the vision system will also track the explored parts of the map (Seen)
	*/
	public function visit(x : Float, y : Float, radius : Float) : Void
	{
		var tx = Math.floor(x / tilesize);
		var ty = Math.floor(y / tilesize);
		//trace("Vision.visit : x=" + x + ", y=" + y + ", tx=" + tx + ", ty=" + ty);

		var radiusGrid : Grid = getRadiusGrid(radius);

		stamp(radiusGrid, tx, ty);

		//setTile(tx, ty, IVision.Full);
	}


	/////////////////////////////////////////////////////////////
	// private parts
	/////////////////////////////////////////////////////////////


	/*
		stamp the grid with given 'stamp'
		the given coordinates mark the stamp center target tile
	*/
	private function stamp(radiusGrid : Grid, tx : Int, ty : Int)
	{
		var tr : Int = Math.round((radiusGrid.length - 1) / 2);

		//trace("Vision.stamp gridlength=" + radiusGrid.length + " tr=" + tr);

		var rx : Int = 0;
		for(x in tx-tr...tx+tr+1)
		{
			var ry : Int = 0;
			for(y in ty-tr...ty+tr+1)
			{
				if(inBounds(x, y))
				{
					if(tiles[x][y].value == IVision.None)
					{
						if(radiusGrid[rx][ry].value != IVision.None)
						{
							setTile(x, y, radiusGrid[rx][ry].value);
						}
					}
				}
				ry++;
			}
			rx++;
		}
	}

	/*
		get a vision 'stamp' for the given radius
	*/
	private function getRadiusGrid(radius : Float)
	{
		var radiusID : String = Std.string(Math.round(radius));

		if(!radiusGridCache.exists(radiusID))
		{
			//trace("new radius grid: " + radiusID);
			radiusGridCache.set(radiusID, newRadiusGrid(radius));	
		}

		return radiusGridCache.get(radiusID);
	}

	/*
		instanciate a new vision 'stamp' for the given radius
	*/
	private function newRadiusGrid(radius : Float) : Grid
	{
		var mid : Int = Math.ceil(radius / tilesize);
		var size : Int = (mid * 2) + 1;

		//trace("Vision.newRadiusGrid radius=" + radius + " mid=" + mid + " size=" + size);

		var radiusgrid : Grid = newGrid(size, size);

		for(x in 0...size)
		{
			for(y in 0...size)
			{
				if(distance(x, y, mid, mid) <= radius)
				{
					//trace("Vision.newRadiusGrid within radius " + radius);
					radiusgrid[x][y].value = IVision.Full;
				}
				else
				{
					//trace("Vision.newRadiusGrid NOT within radius " + radius);
					//radiusgrid[x][y].value = IVision.Seen;
				}
			}
		}

		return radiusgrid;
	}

	/*
		calculate the distance in pixels between two tile centers
	*/
	private function distance(x1 : Int, y1 : Int, x2 : Int, y2 : Int) : Float
	{
		var d : Float = tilesize * Math.sqrt(Math.pow(x1 - x2, 2) + Math.pow(y1 - y2, 2));
		//trace("Vision.distance ("+x1+","+y1+")-("+x2+","+y2+") = " + d);
		return d;
	}

	/*
		instanciate a new vision tile grid
	*/
	private function newGrid(rows : Int, cols : Int) : Grid
	{
		var grid = new Grid();

		for(x in 0...cols)
		{
			grid[x] = new Array<IVisionTile>();
			for(y in 0...rows)
			{
				grid[x][y] = 
				{
					tx : x, 
					ty : y, 
					value : IVision.None, 
					rect : new Rectangle(x*tilesize, y*tilesize, tilesize, tilesize),
					point : new Point(x*tilesize, y*tilesize)
					//add smoothing information later
				};
			}
		}

		return grid;
	}

	/*
		set a vision state to a tile
		if the vision state has altered, broadcast the vision change
	*/
	private function setTile(tx : Int, ty : Int, v : IVision)
	{
		if(inBounds(tx, ty))
		{
			if(tiles[tx][ty].value == v)
			{
				// do nothing. Already seen.
			}
			else
			{
				tiles[tx][ty].value = v;
				broadcastChange(tx, ty);
			}
		}
	}

	/*
		check if tile coordinates are within the bounds of our vision tile grid
	*/
	private function inBounds(tx : Int, ty : Int) : Bool
	{
		if(tx < 0 || tx >= cols)
		{
			return false;
		}
		else if(ty < 0 || ty >= rows)
		{
			return false;
		}
		else
		{
			return true;
		}
	}

	/*
		let our client objects know something has changed in the players vision
		for example, a 'fog of war' object may want to paint fog where the player can't see
	*/
	private function broadcastChange(tx : Int, ty : Int)
	{
		for(idx in 0...clientRegistry.length)
		{
			clientRegistry[idx].onVisionChange(tiles[tx][ty]);
		}
	}
}