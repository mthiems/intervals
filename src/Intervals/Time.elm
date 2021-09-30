module Intervals.Time exposing (..)


import Time
import Time.Extra as T
import TimeExtra as T
import Round


type alias Time =
  { timestamp : Time.Posix
  , zone : Time.Zone
  , isFirst : Bool
  , unit : Unit
  , multiple : Int
  , change : Maybe Unit
  }


type Unit
  = Millisecond
  | Second
  | Minute
  | Hour
  | Day
  | Month
  | Year


values : Time.Zone -> Int -> Time.Posix -> Time.Posix -> List Time
values zone maxMmount min max =
  let ( unit, mult ) = toBestUnit zone maxMmount min max
      amount = getNumOfTicks zone unit mult min max
      initial = ceilingUnit zone unit mult min
      tUnit = toExtraUnit unit

      toTicks xs acc =
        case xs of
          x :: rest ->
            let prev = T.add tUnit ((x - 1) * mult) zone initial
                curr = T.add tUnit (x * mult) zone initial
                change = getChange zone prev curr
            in
            toTicks rest (toTick x curr change :: acc)

          [] ->
            acc

      toTick x timestamp change =
        { timestamp = timestamp
        , zone = zone
        , isFirst = x == 0
        , unit = unit
        , multiple = mult
        , change = if unitToInt change > unitToInt unit then Just change else Nothing
        }
  in
  List.reverse <| toTicks (List.range 0 (amount - 1)) []


toBestUnit : Time.Zone -> Int -> Time.Posix -> Time.Posix -> ( Unit, Int )
toBestUnit zone amount min max =
  let toNice unit =
        let niceNums = niceMultiples unit
            maybeNiceNum = List.filter (\n -> getNumOfTicks zone unit n min max <= amount) niceNums
            div n1 n2 = ceiling (toFloat n1 / toFloat n2)
        in
        case List.head maybeNiceNum of
          Just niceNum ->
            ( unit, niceNum )

          Nothing ->
            case largerUnit unit of
              Just larger -> toNice larger
              Nothing -> ( Year, 100000000 )
  in
  toNice Millisecond


getNumOfTicks : Time.Zone -> Unit -> Int -> Time.Posix -> Time.Posix -> Int
getNumOfTicks zone unit mult a b =
  let diff property =
        let ceiled = ceilingUnit zone unit mult a in
        if toMs ceiled > toMs b then -1
        else div (property (getDiff zone ceiled b)) mult

      timeDiff ms =
        let ceiled = ceilingUnit zone unit mult a in
        if toMs ceiled > toMs b then -1
        else div (div (toMs b - toMs ceiled) ms) mult

      div n1 n2 =
        floor (toFloat n1 / toFloat n2)
  in
  case unit of
    Millisecond -> timeDiff oneMs + 1
    Second -> timeDiff oneSecond + 1
    Minute -> timeDiff oneMinute + 1
    Hour -> timeDiff oneHour + 1
    Day -> timeDiff oneDay + 1
    Month -> diff (\d -> d.month + d.year * 12) + 1
    Year -> diff .year + 1


getChange : Time.Zone -> Time.Posix -> Time.Posix -> Unit
getChange zone a b =
  let aP = T.posixToParts zone a
      bP = T.posixToParts zone b
  in
  if aP.year /= bP.year then Year else
  if aP.month /= bP.month then Month else
  if aP.day /= bP.day then Day else
  if aP.hour /= bP.hour then Hour else
  if aP.minute /= bP.minute then Minute else
  if aP.second /= bP.second then Second else
  Millisecond


niceMultiples : Unit -> List Int
niceMultiples unit =
  case unit of
    Millisecond -> [ 1, 2, 5, 10, 20, 25, 50, 100, 200, 500 ]
    Second      -> [ 1, 2, 5, 10, 15, 30 ]
    Minute      -> [ 1, 2, 5, 10, 15, 30 ]
    Hour        -> [ 1, 2, 3, 4, 6, 8, 12 ]
    Day         -> [ 1, 2, 3, 7, 14 ]
    Month       -> [ 1, 2, 3, 4, 6 ]
    Year        -> [ 1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000, 10000, 1000000, 10000000 ]



-- HELPERS


type alias Diff =
    { year : Int
    , month : Int
    , day : Int
    , hour : Int
    , minute : Int
    , second : Int
    , millisecond : Int
    }


getDiff : Time.Zone -> Time.Posix -> Time.Posix -> Diff
getDiff zone a b =
  let ( aP, bP ) =
        if toMs a < toMs b then
          ( T.posixToParts zone a
          , T.posixToParts zone b
          )
        else
          ( T.posixToParts zone b
          , T.posixToParts zone a
          )

      dMsX = bP.millisecond - aP.millisecond
      dMs = if dMsX < 0 then 1000 + dMsX else dMsX

      dSecondX = bP.second - aP.second + (if dMsX < 0 then -1 else 0)
      dSecond = if dSecondX < 0 then 60 + dSecondX else dSecondX

      dMinuteX = bP.minute - aP.minute + (if dSecondX < 0 then -1 else 0)
      dMinute = if dMinuteX < 0 then 60 + dMinuteX else dMinuteX

      dHourX = bP.hour - aP.hour + (if dMinuteX < 0 then -1 else 0)
      dHour = if dHourX < 0 then 24 + dHourX else dHourX

      dDayX = bP.day - aP.day + (if dHourX < 0 then -1 else 0)
      dDay = if dDayX < 0 then T.daysInMonth bP.year bP.month + dDayX else dDayX

      dMonthX = monthAsInt bP.month - monthAsInt aP.month + (if dDayX < 0 then -1 else 0)
      dMonth = if dMonthX < 0 then 12 + dMonthX else dMonthX

      dYearX = bP.year - aP.year + (if dMonthX < 0 then -1 else 0)
      dYear = if dYearX < 0 then monthAsInt bP.month + dYearX else dYearX
  in
  { year = dYear
  , month = dMonth
  , day = dDay
  , hour = dHour
  , minute = dMinute
  , second = dSecond
  , millisecond = dMs
  }


unitFromDiff : Unit -> Diff -> Int
unitFromDiff unit diff =
  case unit of
    Millisecond -> diff.millisecond
    Second -> diff.second
    Minute -> diff.minute
    Hour -> diff.hour
    Day -> diff.day
    Month -> diff.month
    Year -> diff.year


largerUnit : Unit -> Maybe Unit
largerUnit unit =
  case unit of
    Millisecond -> Just Second
    Second -> Just Minute
    Minute -> Just Hour
    Hour -> Just Day
    Day -> Just Month
    Month -> Just Year
    Year -> Nothing


smallerUnit : Unit -> Maybe Unit
smallerUnit unit =
  case unit of
    Millisecond -> Nothing
    Second -> Just Millisecond
    Minute -> Just Second
    Hour -> Just Minute
    Day -> Just Hour
    Month -> Just Day
    Year -> Just Month


unitToInt : Unit -> Int
unitToInt unit =
  case unit of
    Millisecond -> 0
    Second -> 1
    Minute -> 2
    Hour -> 3
    Day -> 4
    Month -> 5
    Year -> 6


toExtraUnit : Unit -> T.Interval
toExtraUnit unit =
  case unit of
    Millisecond -> T.Millisecond
    Second -> T.Second
    Minute -> T.Minute
    Hour -> T.Hour
    Day -> T.Day
    Month -> T.Month
    Year -> T.Year


monthAsInt : Time.Month -> Int
monthAsInt month =
  case month of
    Time.Jan -> 1
    Time.Feb -> 2
    Time.Mar -> 3
    Time.Apr -> 4
    Time.May -> 5
    Time.Jun -> 6
    Time.Jul -> 7
    Time.Aug -> 8
    Time.Sep -> 9
    Time.Oct -> 10
    Time.Nov -> 11
    Time.Dec -> 12


intAsMonth : Int -> Time.Month
intAsMonth int =
  case int of
    1 -> Time.Jan
    2 -> Time.Feb
    3 -> Time.Mar
    4 -> Time.Apr
    5 -> Time.May
    6 -> Time.Jun
    7 -> Time.Jul
    8 -> Time.Aug
    9 -> Time.Sep
    10 -> Time.Oct
    11 -> Time.Nov
    12 -> Time.Dec
    _ -> Time.Dec


toMs : Time.Posix -> Int
toMs =
  Time.posixToMillis


fromMs : Int -> Time.Posix
fromMs =
  Time.millisToPosix


oneMs : Int
oneMs =
  1


oneSecond : Int
oneSecond =
  1000


oneMinute : Int
oneMinute =
  oneSecond * 60


oneHour : Int
oneHour =
  oneMinute * 60


oneDay : Int
oneDay =
  oneHour * 24



-- ROUND DATES / FLOOR


floorUnit : Time.Zone -> Unit -> Int -> Time.Posix -> Time.Posix
floorUnit zone unit mult =
  case unit of
    Millisecond -> floorMs zone mult
    Second -> floorSecond zone mult
    Minute -> floorMinute zone mult
    Hour -> floorHour zone mult
    Day -> floorDay zone mult
    Month -> floorMonth zone mult
    Year -> floorYear zone mult


floorMs : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorMs zone mult stamp =
  let parts = T.posixToParts zone stamp
      rem = remainderBy mult parts.millisecond
  in
  if rem == 0
  then T.partsToPosix zone parts
  else T.add T.Millisecond -rem zone stamp


floorSecond : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorSecond zone mult stamp =
  let parts = T.posixToParts zone (T.floor T.Second zone stamp)
      rem = remainderBy mult parts.second
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Second -rem zone stamp


floorMinute : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorMinute zone mult stamp =
  let parts = T.posixToParts zone (T.floor T.Minute zone stamp)
      rem = remainderBy mult parts.minute
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Minute -rem zone new


floorHour : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorHour zone mult stamp =
  let parts = T.posixToParts zone (T.floor T.Hour zone stamp)
      rem = remainderBy mult parts.hour
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Hour -rem zone new


floorDay : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorDay zone mult stamp =
  if mult == 7 then
    T.floor T.Week zone stamp
  else
    T.floor T.Day zone stamp


floorMonth : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorMonth zone mult stamp =
  let parts = T.posixToParts zone (T.floor T.Month zone stamp)
      monthInt = monthAsInt parts.month
      rem = remainderBy mult (monthInt - 1)
      newMonth = if rem == 0 then monthInt else monthInt - rem
  in
  T.partsToPosix zone { parts | month = intAsMonth newMonth }


floorYear : Time.Zone -> Int -> Time.Posix -> Time.Posix
floorYear zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Year zone stamp)
      rem = remainderBy mult parts.year
      newYear = if rem == 0 then parts.year else parts.year - rem
  in
  T.partsToPosix zone { parts | year = newYear }



-- CEILING


ceilingUnit : Time.Zone -> Unit -> Int -> Time.Posix -> Time.Posix
ceilingUnit zone unit mult =
  case unit of
    Millisecond -> ceilingMs zone mult
    Second -> ceilingSecond zone mult
    Minute -> ceilingMinute zone mult
    Hour -> ceilingHour zone mult
    Day -> ceilingDay zone mult
    Month -> ceilingMonth zone mult
    Year -> ceilingYear zone mult


ceilingMs : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingMs zone mult stamp =
  let parts = T.posixToParts zone stamp
      rem = remainderBy mult parts.millisecond
  in
  if rem == 0
  then T.partsToPosix zone parts
  else T.add T.Millisecond (mult - rem) zone stamp


ceilingSecond : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingSecond zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Second zone stamp)
      rem = remainderBy mult parts.second
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Second (mult - rem) zone new


ceilingMinute : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingMinute zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Minute zone stamp)
      rem = remainderBy mult parts.minute
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Minute (mult - rem) zone new


ceilingHour : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingHour zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Hour zone stamp)
      rem = remainderBy mult parts.hour
      new = T.partsToPosix zone parts
  in
  if rem == 0
  then new
  else T.add T.Hour (mult - rem) zone new


ceilingDay : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingDay zone mult stamp =
  if mult == 7 then
    T.ceiling T.Week zone stamp
  else
    T.ceiling T.Day zone stamp


ceilingMonth : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingMonth zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Month zone stamp)
      monthInt = monthAsInt parts.month -- 12
      rem = remainderBy mult (monthInt - 1) -- 11 % 3 = 2
      newMonth = if rem == 0 then monthInt else monthInt - rem + mult -- 12 - 2 + 3 = 13
  in
  T.partsToPosix zone <|
    if newMonth > 12
    then { parts | year = parts.year + 1, month = intAsMonth (newMonth - 12) }
    else { parts | month = intAsMonth newMonth }


ceilingYear : Time.Zone -> Int -> Time.Posix -> Time.Posix
ceilingYear zone mult stamp =
  let parts = T.posixToParts zone (T.ceiling T.Year zone stamp)
      rem = remainderBy mult parts.year
      newYear = if rem == 0 then parts.year else parts.year - rem + mult
  in
  T.partsToPosix zone { parts | year = newYear }

