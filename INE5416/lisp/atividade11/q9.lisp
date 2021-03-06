(defun read_int(str)
    (write str)
    (parse-integer (read-line)) 
)

(defun dist(x1 y1 z1 x2 y2 z2)
    (sqrt (+ (+ (expt (- x1 x2) 2) (expt (- y1 y2) 2)) (expt (- z1 z2) 2)))
)

(defun main()
    (write-line "Distância de dois pontos 3D")
    (setq x1 (read_int "x1:"))
    (setq y1 (read_int "y1:"))
    (setq z1 (read_int "z1:"))
    (setq x2 (read_int "x2:"))
    (setq y2 (read_int "y2:"))
    (setq z2 (read_int "z2:"))
    (write-line (write-to-string (dist x1 y1 z1 x2 y2 z2))) 
)

(main)