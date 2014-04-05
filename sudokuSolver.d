import std.range, std.algorithm, std.string, std.conv;

//sudoku Information
enum int squareWidth = 3;
enum int squareHeight = 3;
enum int boardSide = squareWidth * squareHeight;
enum int boardSize = boardSide ^^ 2;

/** 
* A sudokuCell is a collection of bits.
* The first bit signifies if that cell is occupied and all other bits represent possibilities.
* 0b011 => 1 and 2 are possibilities.
* 0b1001 => the cell is occupied and 1 is it's value.
* Using bits to represent possibilities was the idea of Timon Gehr
**/

// SudokuCell contains only values in the range (0, everythingPossible)
static if (boardSide < short.sizeof * 8) {
     alias ushort SudokuCell;
} else static if (boardSide < uint.sizeof * 8) {
     alias uint SudokuCell;
} else static if (boardSide < ulong.sizeof * 8) {
     alias ulong SudokuCell;
} else //maybe add ucent here?
     static assert(false, "BoardSide is too big, no value has enough bits to store all possibilities in.");

//everything possible, the default value of every Sudoku cell
enum SudokuCell everythingPossible = cast(SudokuCell) (2 ^^ boardSide - 1);

//xor this with a cell to toggle occupation
enum SudokuCell occupiedBit = 1 << boardSide;

alias SudokuCell[boardSize] SudokuField; // returns the possibilities in a cell at a given index

bool isOccupied(ref SudokuCell toValidate) pure nothrow{
	return (toValidate & occupiedBit) == occupiedBit;
}

/**
* returns a range containing all possibilities for a given sudokuCell
* for example, bitsetToRange(0b011) returns 1,2
**/
auto bitsetToRange(in SudokuCell x) {
    // bit shift it and check the last bit. if it's one, that number is a possibility
    return array(iota(boardSide).filter!(i => (x >> i) & 1)().map!(x=>x+1)());
}

/**
* Inlined array with variable (but limited) length.
* speeds things up considerably
**/
struct MaxArray(T, size_t maxLen) {
    T[maxLen] data;
    private uint len;
    alias items this;

    void opAssign(T[] a) pure nothrow {
        this.data[0 .. a.length] = a;
        this.len = cast(typeof(len))a.length;
    }

    @property T[] items() pure nothrow {
        return data[0 .. len];
    }
}

///cachedBitsetToRange[x] gets translated to bitsetToRange(x) but the result is pre-calculated
__gshared static MaxArray!(int, boardSide)[] cachedBitsetToRange = generateBitsetCache(); //using dynamic arrays because statics have a low storage ceiling (boardSide<=18)

// easy to cache, very few possibilities (2 ^^ boardSide)
MaxArray!(int, boardSide)[] generateBitsetCache() {
	MaxArray!(int, boardSide)[] cache;
	
	foreach(SudokuCell x;0..2^^boardSide){
		MaxArray!(int, boardSide) temp;
		temp=bitsetToRange(x);
		cache~=temp;
	}
	return cache;
}

/**
* put a certain possibility at a given index and update all possibilities in it's region
**/
void put(ref SudokuField sudokuField, in int possibility, in uint index)
 nothrow pure in {
    // valid possibility
    assert(possibility >= 1 && possibility <= boardSide);
    assert(!sudokuField[index].isOccupied());
} body {
    immutable bitRepresentation = cast(SudokuCell)(1 << (possibility - 1));

    // compute the inverse and "and" it, that way we filter out "possibility"
    immutable SudokuCell mask = everythingPossible ^ bitRepresentation ^ occupiedBit;

    // 0b000000001 => 0b111111110
    // every & operation will thus remove the given possibility

    immutable uint rowIndex = index / boardSide;
    immutable uint collIndex = index % boardSide;

    foreach (ref c; sudokuField[rowIndex * boardSide .. (rowIndex + 1) * boardSide])
        c &= mask;

    foreach (x; 0 .. boardSide)
        sudokuField[x * boardSide + collIndex] &= mask;

    immutable uint squareRowStart = rowIndex / squareHeight * squareHeight;
    immutable uint squareColStart = collIndex / squareWidth * squareWidth;

    foreach (t; 0 .. boardSide)
        sudokuField[(squareRowStart + t / squareWidth) * boardSide + squareColStart + t % squareHeight] &= mask;

    sudokuField[index] = bitRepresentation ^ occupiedBit; //Fill in the cell and toggle occupation
}


/**
* Solves single candidates and searches for the cell with the least amount of possibilities.
* Returns -1 if the sudoku contains an empty field. (no possibilities)
* Returns the field with the least possibilities on success.
* Returns the boardSize if everything was solved.
*/
int optimize(ref SudokuField sudokuField) nothrow{
    int returnValue = boardSize;
    size_t leastPossibilities = boardSide + 1;

    foreach (int i, x; sudokuField) {
		if(isOccupied(x))
			continue;
			
        immutable curLength = cachedBitsetToRange[x].length;

        switch (curLength) {
            case 0: // no possibilities
                return -1;
            case 1:
                put(sudokuField, cachedBitsetToRange[x][0], i);
                break;
            default:
                if (curLength < leastPossibilities) {
                    returnValue = i;
                    leastPossibilities = curLength;
                }
        }
    }

    return returnValue;
}

/**
* The actual brute force solving.
**/
bool backtrack(ref SudokuField sudokuField) nothrow{
    immutable int index = optimize(sudokuField);

	switch(index){
		case boardSize: //finished
			return true;
		case -1: //contained an empty field (error occurred earlier)
			return false;
		default:	
	}

    // foreach loop will destroy these but we may need to restore the sudokuField
    SudokuField backupSudokuField = sudokuField;

    foreach (curPossibility; cachedBitsetToRange[sudokuField[index]]){
		put(sudokuField, curPossibility, index);

        if (backtrack(sudokuField))
            return true;

        // it failed, restore everything
        sudokuField = backupSudokuField;
    }
	
    return false;
}

/**
* Takes the sudokuField which is filled with possibilities and transforms it back in the original format.
**/
string prettyPrint(SudokuField sudokuField){
	string returnText;
	
	foreach(i,cell;sudokuField){
		cell ^= occupiedBit;
		
		if(cachedBitsetToRange[cell].length!=1)
			return "The Sudoku is unsolvable.";
		
		int intSolution=cachedBitsetToRange[cell][0];
		
		returnText~=to!string(intSolution);
		
		if(boardSide>9)
			returnText~=" ";
	}
	
	return returnText;
}

void main(in string[] args) {
    import std.stdio, std.datetime;

    if (args.length < 2) {
        writeln("Usage: ", args[0], " <sudoku>");
        return;
    }

    SudokuField sudokuField = everythingPossible;
	
	//if bigger then 9, we have to use a different notation...
	if(boardSide>9){
		if(args.length-1!=boardSize){
				writeln("The sudoku you entered is not a ",boardSide,"x",boardSide," sudoku.");
				return;
		}
		foreach(int index,curent;args[1..$]){
			if(isNumeric(curent)){
				int possibility=to!int(curent);
				
				if(possibility<=boardSide && possibility>0)
						put(sudokuField, possibility, index);
				
			}
		}
	}else{
		if(args[1].length!=boardSize){
			writeln("The sudoku you entered is not a ",boardSide,"x",boardSide," sudoku.");
			return;
		}
		foreach(uint index,char c;args[1]){
			if(inPattern(c, "1-9")){
				int possibility = c - '0';
				
				if(possibility<=boardSide)
					put(sudokuField, possibility, index);
			}
		}
	}
	
    StopWatch sw;
	
	sw.start();
	
    backtrack(sudokuField);

	sw.stop();
	
    writeln("Solved in ", sw.peek().nsecs , " nanoseconds.");
    writeln(prettyPrint(sudokuField));
}
