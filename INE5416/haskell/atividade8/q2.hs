module Ponto(Ponto (Ponto2D),
             distancia,
             colineares,
             formaTriangulo) where

    data Ponto = Ponto2D (Float, Float)

    distancia :: Ponto -> Ponto -> Float
    distancia (Ponto2D (x1, y1)) (Ponto2D (x2, y2)) = (sqrt ((x1-x2)^2 + (y1-y2)^2))

    colineares :: Ponto -> Ponto -> Ponto -> Bool
    colineares (Ponto2D (x1, y1)) (Ponto2D (x2, y2)) (Ponto2D (x3, y3)) = (x1*y2 + y1*x3 + x2*y3 - (x3*y2 + x1*y3 + x2*y1)) == 0

    formaTriangulo :: Ponto -> Ponto -> Ponto -> Bool
    formaTriangulo p1 p2 p3 = not (colineares p1 p2 p3)