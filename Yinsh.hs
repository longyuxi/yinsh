module Yinsh where

import Control.Monad (guard)
import qualified Data.Map as M
import Data.List (delete, foldl')

-- $setup
-- >>> import Data.List (sort, nub)
-- >>> import Test.QuickCheck hiding (vector)
-- >>> let boardCoords = elements coords
-- >>> instance Arbitrary Direction where arbitrary = elements directions

-- | Yinsh hex coordinates
type YCoord = (Int, Int)

-- | The six hex directions
data Direction = N | NE | SE | S | SW | NW
                 deriving (Eq, Enum, Bounded, Show)

data Element = Ring Player
             | Marker Player
             deriving (Show, Eq)

data TurnMode = AddRing
              | AddMarker
              | MoveRing YCoord
              | RemoveRun
              | RemoveRing
              | PseudoTurn
              deriving (Eq, Show)

-- | Player types: black & white or blue & green
data Player = B | W
              deriving (Eq, Enum, Bounded, Show)

-- | Efficient data structure for the board with two-way access.
-- The Map is used to get log(n) access to the element at a certain
-- coordinate while the lists are used to get direct access to the
-- coordinates of the markers and rings (which would need a reverse
-- lookup otherwise). This comes at the cost of complete redundancy.
-- Either bmap or the other four fields would be enough to reconstruct
-- the whole board.
data Board = Board { bmap :: M.Map YCoord Element
                   , ringsB :: [YCoord]
                   , ringsW :: [YCoord]
                   , markersB :: [YCoord]
                   , markersW :: [YCoord]
                   } deriving (Show)

data GameState = GameState
    { activePlayer :: Player
    , turnMode :: TurnMode
    , board :: Board
    , pointsB :: Int
    , pointsW :: Int
    } deriving Show

markers :: Player -> Board -> [YCoord]
markers B = markersB
markers W = markersW

rings :: Player -> Board -> [YCoord]
rings B = ringsB
rings W = ringsW

-- occupied :: Board -> [YCoord]
-- occupied b = M.keys (bmap b)

elementAt :: Board -> YCoord -> Maybe Element
elementAt b c = M.lookup c (bmap b)

-- | Check if a certain point on the board is free
freeCoord :: Board -> YCoord -> Bool
freeCoord b c = not $ M.member c (bmap b)

addElement :: Board -> YCoord -> Element -> Board
addElement b c e = case e of
                       Ring B -> b { bmap = bmap'
                                   , ringsB = c : ringsB b }
                       Ring W -> b { bmap = bmap'
                                   , ringsW = c : ringsW b }
                       Marker B -> b { bmap = bmap'
                                   , markersB = c : markersB b }
                       Marker W -> b { bmap = bmap'
                                   , markersW = c : markersW b }
    where bmap' = M.insert c e (bmap b)

removeElement :: Board -> YCoord -> Board
removeElement b c = case e of
                       Ring B -> b { bmap = bmap'
                                   , ringsB = delete c (ringsB b) }
                       Ring W -> b { bmap = bmap'
                                   , ringsW = delete c (ringsW b) }
                       Marker B -> b { bmap = bmap'
                                   , markersB = delete c (markersB b) }
                       Marker W -> b { bmap = bmap'
                                   , markersW = delete c (markersW b) }
    where bmap' = M.delete c (bmap b)
          e = bmap b M.! c

-- TODO: this can certainly be optimizied:
modifyElement :: Board -> YCoord -> Element -> Board
modifyElement b c = addElement (removeElement b c) c

emptyBoard :: Board
emptyBoard = Board { bmap = M.empty
                   , ringsB = []
                   , ringsW = []
                   , markersB = []
                   , markersW = []
                   }

-- Game behaviour
pointsForWin = 2
pointsForWin :: Int

-- | Similar to Enum's succ, but for cyclic data structures.
-- Wraps around to the beginning when it reaches the 'last' element.
next :: (Eq a, Enum a, Bounded a) => a -> a
next x | x == maxBound = minBound
       | otherwise     = succ x

-- | All directions
directions :: [Direction]
directions = [minBound .. maxBound]

-- | Opposite direction
--
-- prop> (opposite . opposite) d == d
opposite :: Direction -> Direction
opposite = next . next . next

-- | Vector to the next point on the board in a given direction
vector :: Direction -> YCoord
vector N  = ( 0,  1)
vector NE = ( 1,  1)
vector SE = ( 1,  0)
vector S  = ( 0, -1)
vector SW = (-1, -1)
vector NW = (-1,  0)

-- could be generated by generating all triangular lattice points smaller
-- than a certain cutoff (~ 5)
numPoints :: [[Int]]
numPoints = [[2..5], [1..7], [1..8], [1..9],
             [1..10], [2..10], [2..11], [3..11],
             [4..11], [5..11], [7..10]]

-- | All points on the board
--
-- >>> length coords
-- 85
--
coords :: [YCoord]
coords = concat $ zipWith (\list ya -> map (\x -> (ya, x)) list) numPoints [1..]

-- | Check if two points are connected by a line
--
-- >>> connected (3, 4) (8, 4)
-- True
--
-- prop> connected c1 c2 == connected c2 c1
--
connected :: YCoord -> YCoord -> Bool
connected (x, y) (a, b) =        x == a
                          ||     y == b
                          || x - y == a - b

-- | List of points reachable from a certain point
--
-- Every point should be reachable within two moves
-- prop> forAll boardCoords (\c -> sort coords == sort (nub (reachable c >>= reachable)))
--
reachable :: YCoord -> [YCoord]
reachable c = filter (connected c) coords

-- | Vectorially add two coords
add :: YCoord -> YCoord -> YCoord
add (x1, y1) (x2, y2) = (x1 + x2, y1 + y2)

-- | Vectorially subtract two coords
sub :: YCoord -> YCoord -> YCoord
sub (x1, y1) (x2, y2) = (x1 - x2, y1 - y2)

-- | Scalar product
prod :: YCoord -> YCoord -> Int
prod (x1, y1) (x2, y2) = x1 * x2 + y1 * y2

-- | Square norm
norm2 :: YCoord -> Int
norm2 (x, y) = x * x + y * y

-- | Get all valid ring moves starting from a given point
validRingMoves :: Board -> YCoord -> [YCoord]
validRingMoves b start = filter (freeCoord b) $ concatMap (validInDir False start) directions
    where markerPos = markersB b ++ markersW b
          ringPos   = ringsB b ++ ringsW b
          validInDir :: Bool -> YCoord -> Direction -> [YCoord]
          validInDir jumped c d = c : rest
              where nextPoint = c `add` vector d
                    rest = if nextPoint `elem` coords && nextPoint `notElem` ringPos
                           then if nextPoint `elem` markerPos
                                then validInDir True nextPoint d
                                else if jumped
                                     then [nextPoint]
                                     else validInDir False nextPoint d
                           else []

-- | Get all nearest neighbors
--
-- Every point has neighbors
--
-- >>> sort coords == sort (nub (coords >>= neighbors))
-- True
--
-- Every point is a neighbor of its neighbor
-- prop> forAll boardCoords (\c -> c `elem` (neighbors c >>= neighbors))
--
neighbors :: YCoord -> [YCoord]
neighbors c = filter (`elem` coords) adj
    where adj = mapM (add . vector) directions c

-- | Check if a player has a run of five in a row
hasRun [] = False
hasRun ms@(m:rest) = partOfRun (filter (connected m) ms) m || hasRun rest
-- TODO: is this part          ^^^^^^^^^^^^^^^^^^^^^^^^^
--       really increasing performance? (can be replace by 'ms')
-- TODO: is it useful to introduce sth like: (length ms >= 5) && ... ?

-- | Check if a coordinate is one of five in a row
--
-- prop> partOfRun (take 5 $ adjacent c d) c == True
partOfRun :: [YCoord] -> YCoord -> Bool
partOfRun ms start = any (partOfRunD ms start) [NW, N, NE]

partOfRunD :: [YCoord] -> YCoord -> Direction -> Bool
partOfRunD ms start dir = length (runCoordsD ms start dir) == 5

-- | Return the coordinates of the markers making up a run
runCoords :: [YCoord] -> YCoord -> [YCoord]
runCoords ms start = if null cs then [] else head cs
    where cs = filter ((== 5) . length) $ map (runCoordsD ms start) [NW, N, NE]

-- | Combine two lists by taking elements alternatingly. If one list is longer,
-- append the rest.
--
-- prop> zipAlternate [] l == l
-- prop> zipAlternate l [] == l
-- prop> zipAlternate l l  == (l >>= (\x -> [x, x]))
zipAlternate :: [a] -> [a] -> [a]
zipAlternate []     ys = ys
zipAlternate (x:xs) ys = x : zipAlternate ys xs

-- | Get adjacent coordinates in a given direction which could belong to a run.
--
-- prop> runCoordsD (take 7 $ adjacent c d) c d == (take 5 $ adjacent c d)
runCoordsD :: [YCoord] -> YCoord -> Direction -> [YCoord]
runCoordsD ms start dir = if start `elem` ms
                          then take 5 $ zipAlternate right left
                          else []
    where right = takeAvailable dir
          left  = tail $ takeAvailable (opposite dir)  -- use tail to avoid taking the start twice
          takeAvailable d = takeWhile (`elem` ms) $ adjacent start d

-- | Get the adjacent (including start) coordinates in a given direction
adjacent :: YCoord -> Direction -> [YCoord]
adjacent start dir = iterate (`add` vector dir) start

-- | Check if point three is on a line between the first two
--
-- prop> let shift = add (vector d) in between c (shift (shift c)) (shift c)
-- prop> let shift = add (vector d) in not $ between c (shift c) (shift (shift c))
between :: YCoord -> YCoord -> YCoord -> Bool
between a b c = n2x * n2y == (x `prod` y)^2 && n2y < n2x && n2z < n2x
    where x = b `sub` a
          y = c `sub` a
          z = c `sub` b
          n2x = norm2 x
          n2y = norm2 y
          n2z = norm2 z

-- | Get all coordinates connecting two points
coordLine :: YCoord -> YCoord -> [YCoord]
coordLine x y = take (num - 1) $ tail $ iterate (`add` step) x
    where delta = y `sub` x
          step = (reduce (fst delta), reduce (snd delta))
          reduce x = round $ fromIntegral x / fromIntegral num
          num = max (abs (fst delta)) (abs (snd delta))

-- | Flip all markers between two given coordinates
flippedMarkers :: Board -> YCoord -> YCoord -> Board
flippedMarkers b s e = foldl' flipMaybe b (coordLine s e)
    where flipMaybe b c = case elementAt b c of
                              Nothing -> b
                              (Just (Marker B)) -> modifyElement b c (Marker W)
                              (Just (Marker W)) -> modifyElement b c (Marker B)

-- | Get new game state after 'interacting' at a certain coordinate.
newGameState :: GameState -> YCoord -> Maybe GameState
newGameState gs cc = -- TODO: the guards should be (?) unnecessary when calling this function from 'gamestates'
    case turnMode gs of
        AddRing -> do
            guard (freeCoord board' cc)
            Just gs { activePlayer = nextPlayer
                    , turnMode = if numRings < 9 then AddRing else AddMarker
                    , board = addElement board' cc (Ring activePlayer')
                    }
            where numRings = length (ringsB board') + length (ringsW board') -- TODO: length is O(n)... is this a problem? we could use maps/arrays
        AddMarker -> do
            guard (cc `elem` rings activePlayer' board')
            Just gs { turnMode = MoveRing cc
                    , board = addElement removedRing cc (Marker activePlayer')
                    }
        (MoveRing start) -> do
            guard (cc `elem` validRingMoves board' start)
            Just gs { activePlayer = nextPlayer
                    , turnMode = nextTurnMode
                    , board = addElement flippedBoard cc (Ring activePlayer')
                    }
            where nextTurnMode = if hasRun playerMarkers'
                                 then PseudoTurn
                                 else AddMarker -- TODO: other player could have a run
                  flippedBoard = flippedMarkers board' start cc
                  playerMarkers' = markers activePlayer' flippedBoard
        RemoveRun -> do
            guard (partOfRun playerMarkers cc)
            Just gs { turnMode = RemoveRing
                    , board = removedRun
                    }
        RemoveRing -> do
            guard (cc `elem` rings activePlayer' board')
            Just gs { activePlayer = nextPlayer
                    , turnMode = AddMarker -- TODO: other player could have a run
                    , board = removedRing
                    , pointsB = if activePlayer' == B then pointsB gs + 1 else pointsB gs
                    , pointsW = if activePlayer' == W then pointsW gs + 1 else pointsW gs
                    }
        PseudoTurn ->
            Just gs { activePlayer = nextPlayer
                    , turnMode = RemoveRun
                    }
    where activePlayer' = activePlayer gs
          nextPlayer    = next activePlayer'
          removedRing    = removeElement board' cc
          removedRun     = foldl' removeElement board' (runCoords playerMarkers cc)
          board'        = board gs
          playerMarkers = markers activePlayer' board'

initialGameState :: GameState
initialGameState = GameState { activePlayer = B
                             , turnMode = AddRing
                             , board = emptyBoard
                             , pointsW = 0
                             , pointsB = 0
                             }

-- Testing stuff

testBoard :: Board
testBoard = foldl' (\b (c, e) -> addElement b c e) emptyBoard
                [ ((3, 4), Ring B)
                , ((4, 9), Ring B)
                , ((7, 9), Ring B)
                , ((8, 9), Ring B)
                , ((7, 10), Ring B)
                , ((8, 7), Ring W)
                , ((6, 3), Ring W)
                , ((4, 8), Ring W)
                , ((4, 2), Ring W)
                , ((2, 5), Ring W)
                , ((6, 4), Marker W)
                , ((6, 5), Marker W)
                , ((6, 7), Marker W)
                , ((5, 5), Marker W)
                , ((4, 5), Marker W)
                , ((3, 5), Marker W)
                , ((6, 6), Marker B)]

testGameState = GameState { activePlayer = B
                          , turnMode = AddMarker
                          , board = testBoard
                          , pointsW = 0
                          , pointsB = 0
                          }

testGameStateW = GameState { activePlayer = W
                          , turnMode = AddMarker
                          , board = testBoard
                          , pointsW = 0
                          , pointsB = 0
                          }

